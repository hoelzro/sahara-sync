package SaharaSync::Hostd;

use strict;
use warnings;
use feature 'switch';

use Plack::Builder;
use Plack::Request;
use UNIVERSAL;

## NOTE: I should probably just refactor the common functionality of
## the standalone daemon out, and write a separate script that handles
## polling requests for CGI and whatnot, and another separate script
## for the standalone daemon that implements the PSGI spec instead of
## relying on Twiggy.  That way, I don't have to resort to voodoo
## with Twiggy's handles.

## probably replace this with a plugin loader module some day
use SaharaSync::Hostd::Plugin::Store;
use SaharaSync::X::InvalidArgs;
use SaharaSync::X::NoSuchBlob;

my $store = SaharaSync::Hostd::Plugin::Store->get;

my %connections;

sub top_level {
    my ( $env ) = @_;

    my $req = Plack::Request->new($env);
    my $res = $req->new_response;

    unless($req->path eq '/') {
        $res->status(404);
        $res->content_type('text/plain');
        $res->body('not found');
    } else {
        $res->status(200);
        $res->header('X-Sahara-Capabilities' => $env->{'sahara.streaming'} ? 'streaming' : '');
        $res->header('X-Sahara-Version' => $SaharaSync::Hostd::VERSION);
    };
    $res->finalize;
}

sub changes {
    my ( $env ) = @_;

    my $req       = Plack::Request->new($env);
    my $last_sync = $req->header('X-Sahara-Last-Sync');
    my $user      = $req->user;
    my @blobs     = $store->fetch_changed_blobs($user, $last_sync);

    if($env->{'sahara.streaming'}) {
        my $conns = $connections{$user};
        unless($conns) {
            $conns = $connections{$user} = [];
        }

        return sub {
            my ( $respond ) = @_;

            my $writer = $respond->([200, ['Content-Type' => 'text/plain']]);
            push @$conns, $writer;

            $writer->write(join("\n", @blobs));

            # this is REALLY naughty!
            my $h = $writer->{'handle'};
            ## properly clean up connections (I don't think this will do the trick)
            $h->on_error(sub {
                @$conns = grep { $_ ne $writer } @$conns;
            });
            $h->on_eof(sub {
                @$conns = grep { $_ ne $writer } @$conns;
            });
        };
    } else {
        return [
            200,
            ['Content-Type' => 'text/plain'],
            [ join("\n", @blobs) ],
        ];
    }
}

sub blobs {
    my ( $env ) = @_;

    my $req    = Plack::Request->new($env);
    my $res    = $req->new_response;
    my $user   = $req->user;
    my $blob   = $req->path_info;
    my $method = $req->method;

    $blob =~ s!^/!!;

    given($method) {
        when('GET') {
            my ( $handle, $revision ) = $store->fetch_blob($user, $blob);

            if(defined $handle) {
                no warnings 'uninitialized';
                if($req->header('If-None-Match') eq $revision) {
                    $res->status(304);
                } else {
                    $res->status(200);
                    $res->header(ETag => $revision);
                    $res->content_type('application/octet-stream');
                    $res->body($handle);
                }
            } else {
                $res->status(404);
                $res->content_type('text/plain');
                $res->body('not found');
            }
        }
        when('HEAD') {
            my ( undef, $revision ) = $store->fetch_blob($user, $blob);

            if(defined $revision) {
                no warnings 'uninitialized';
                if($req->header('If-None-Match') eq $revision) {
                    $res->status(304);
                } else {
                    $res->status(200);
                    $res->header(ETag => $revision);
                }
            } else {
                $res->status(404);
            }
        }
        when('PUT') {
            my $current_revision = $req->header('If-Match');
            my $revision         = eval {
                $store->store_blob($user, $blob, $req->body, $current_revision);
            };
            if($@) {
                if(UNIVERSAL::isa($@, 'SaharaSync::X::InvalidArgs') ) {
                    $res->status(400);
                    $res->content_type('text/plain');

                    if(defined $current_revision) {
                        $res->body('cannot accept revision when creating a blob');
                    } else {
                        $res->body('revision required for updating a blob');
                    }
                } else {
                    die;
                }
            } else {
                if(defined $revision) {
                    if(defined $current_revision) {
                        $res->status(200);
                    } else {
                        $res->status(201);
                        $res->header(Location => $req->uri);
                    }
                    $res->header(ETag => $revision);
                    $res->content_type('text/plain');
                    $res->body('ok');

                    if($env->{'sahara.streaming'}) {
                        my $conns = $connections{$user};
                        if($conns) {
                            foreach my $writer (@$conns) {
                                $writer->write("$blob\n");
                            }
                        }
                    }
                } else {
                    $res->status(409);
                    $res->content_type('text/plain');
                    $res->body('conflict');
                }
            }
        }
        when('DELETE') {
            my $revision = $req->header('If-Match');

            unless(defined $revision) {
                $res->status(400);
                $res->content_type('text/plain');
                $res->body('revision required');
            } else {
                $revision = eval {
                    $store->delete_blob($user, $blob, $revision);
                };
                if($@) {
                    if(UNIVERSAL::isa($@, 'SaharaSync::X::NoSuchBlob')) {
                        $res->status(404);
                        $res->content_type('text/plain');
                        $res->body('not found');
                    } else {
                        die;
                    }
                } else {
                    if(defined $revision) {
                        $res->status(200);
                        $res->content_type('text/plain');
                        $res->body('ok');

                        if($env->{'sahara.streaming'}) {
                            my $conns = $connections{$user};
                            if($conns) {
                                foreach my $writer (@$conns) {
                                    $writer->write("$blob\n");
                                }
                            }
                        }
                    } else {
                        $res->status(409);
                        $res->content_type('text/plain');
                        $res->body('conflict');
                    }
                }
            }
       }
    }
    $res->finalize;
}

sub to_app {
    builder {
	enable 'Sahara::Streaming';
        mount '/changes' => builder {
            enable 'Options', allowed => [qw/GET/];
            enable 'Sahara::Auth', store => $store;
            \&changes;
        };

        mount '/blobs' => builder {
            enable 'Options', allowed => [qw/GET HEAD PUT DELETE/];
            enable 'Sahara::Auth', store => $store;
            \&blobs;
        };

        mount '/' => builder {
            enable_if { $_[0]->{'REQUEST_URI'} eq '/' } 'Options', allowed => [qw/HEAD/];
            \&top_level;
        };
    };
}

1;

__END__

# ABSTRACT: Host daemon for Sahara Sync

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS
=cut
