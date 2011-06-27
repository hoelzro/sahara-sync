## no critic (RequireUseStrict)
package SaharaSync::Hostd;

## use critic (RequireUseStrict)
use Moose;
use feature 'switch';

use IO::String;
use Plack::Builder;
use Plack::Request;
use Scalar::Util qw(reftype);
use UNIVERSAL;

## NOTE: I should probably just refactor the common functionality of
## the standalone daemon out, and write a separate script that handles
## polling requests for CGI and whatnot, and another separate script
## for the standalone daemon that implements the PSGI spec instead of
## relying on Twiggy.  That way, I don't have to resort to voodoo
## with Twiggy's handles.

use SaharaSync::Stream::Writer;
use SaharaSync::X::InvalidArgs;
use SaharaSync::X::NoSuchBlob;

has storage => (
    is       => 'ro',
    does     => 'SaharaSync::Hostd::Plugin::Store',
    required => 1,
);

has connections => (
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    default  => sub { {} },
);

has git_revision => (
    is       => 'ro',
    isa      => 'Undef|Str',
    init_arg => undef,
    default  => sub {
        my $revision = qx(git rev-parse HEAD 2>/dev/null);
        chomp $revision;

        return $revision || undef;
    },
);

sub BUILDARGS {
    my ( $class, %args ) = @_;

    my $storage = $args{'storage'};
    my $type    = delete $storage->{'type'};
    $type       = 'SaharaSync::Hostd::Plugin::Store::' . $type;
    my $path    = $type;
    $path       =~ s/::/\//g;
    $path       .= '.pm';
    require $path;
    $args{'storage'} = $type->new(%$storage);

    return \%args;
}

sub determine_mime_type {
    my ( $self, $req ) = @_;

    my $accept = $req->header('Accept');
    $accept  ||= 'application/json';

    $accept = 'application/json' if $accept eq '*/*';

    if($accept =~ m!application/json!) {
        return 'application/json';
    } elsif($accept =~ m!application/xml!) {
        return 'application/xml';
    } elsif($accept =~ m!application/x-yaml!) {
        return 'application/x-yaml';
    } else {
        return;
    }
}

sub send_change_to_streams {
    my ( $self, $user, $blob, $metadata ) = @_;

    my $streams = $self->connections->{$user};

    my $changes = {
        name => $blob,
        %$metadata,
    };

    if($streams) {
        foreach my $stream (@$streams) {
            my $meta = $stream->{'metadata'};
            $stream->{'stream'}->write_object({
                map {
                    exists $changes->{$_} ? ($_ => $changes->{$_}) : ()
                } (@$meta, 'revision', 'name', 'is_deleted')
            });
        }
    }
}

sub top_level {
    my ( $self, $env ) = @_;

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

        my $revision = $self->git_revision;
        if(defined $revision) {
            $res->header('X-Sahara-Revision' => $revision);
        }
    };
    $res->finalize;
}

sub changes {
    my ( $self, $env ) = @_;

    my $req         = Plack::Request->new($env);
    my $last_sync   = $req->header('X-Sahara-Last-Sync');
    my $user        = $req->user;
    my @metadata    = $req->query_parameters->get_all('metadata');
    my @blobs       = eval {
        $self->storage->fetch_changed_blobs($user, $last_sync, \@metadata);
    };
    if($@) {
        if(UNIVERSAL::isa($@, 'SaharaSync::X::BadRevision')) {
            return [
                400,
                ['Content-Type' => 'text/plain'],
                ['Bad Revision'],
            ];
        } else {
            die;
        }
    }
    my $connections = $self->connections;

    my $mime_type = $self->determine_mime_type($req);

    if($env->{'sahara.streaming'}) {
        my $conns = $connections->{$user};
        unless($conns) {
            $conns = $connections->{$user} = [];
        }

        return sub {
            my ( $respond ) = @_;

            my $writer = $respond->([200, ['Content-Type' => "$mime_type; charset=utf-8"]]);
            my $stream = SaharaSync::Stream::Writer->for_mimetype($mime_type,
                writer => $writer,
            );
            push @$conns, {
                stream   => $stream,
                metadata => \@metadata,
            };

            $stream->write_objects(@blobs);

            # this is REALLY naughty!
            if(reftype($writer) eq 'HASH') {
                my $h = $writer->{'handle'};
                ## properly clean up connections (I don't think this will do the trick)
                $h->on_error(sub {
                    @$conns = grep { $_ ne $writer } @$conns;
                });
                $h->on_eof(sub {
                    @$conns = grep { $_ ne $writer } @$conns;
                });
            }
        };
    } else {
        my $body = IO::String->new;
        my $writer = SaharaSync::Stream::Writer->for_mimetype($mime_type,
            writer => $body,
        );
        $body = $body->string_ref;
        $writer->write_objects(@blobs);
        $writer->close;
        $body = $$body;

        return [
            200,
            ['Content-Type' => "$mime_type; charset=utf-8"],
            [ $body ],
        ];
    }
}

sub blobs {
    my ( $self, $env ) = @_;

    my $req    = Plack::Request->new($env);
    my $res    = $req->new_response;
    my $user   = $req->user;
    my $blob   = $req->path_info;
    my $method = $req->method;

    $blob =~ s!^/!!;

    given($method) {
        when('GET') {
            my ( $handle, $metadata ) = $self->storage->fetch_blob($user, $blob);
            my $revision = delete $metadata->{'revision'};

            if(defined $handle) {
                no warnings 'uninitialized';
                if($req->header('If-None-Match') eq $revision) {
                    $res->status(304);
                } else {
                    $res->status(200);
                    $res->header(ETag => $revision);
                    foreach my $k (keys %$metadata) {
                        my $v = $metadata->{$k};
                        $k =~ s/^(.)/uc $1/ge;
                        $res->header("X-Sahara-$k", $v);
                    }
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
            my ( $handle, $metadata ) = $self->storage->fetch_blob($user, $blob);
            my $revision = delete $metadata->{'revision'};

            if(defined $revision) {
                no warnings 'uninitialized';
                if($req->header('If-None-Match') eq $revision) {
                    $res->status(304);
                } else {
                    $res->status(200);
                    foreach my $k (keys %$metadata) {
                        my $v = $metadata->{$k};
                        $k =~ s/^(.)/uc $1/ge;
                        $res->header("X-Sahara-$k", $v);
                    }
                    $res->header(ETag => $revision);

                    my $size = 0;
                    do {
                        local $/ = \4096;
                        while(defined(my $line = $handle->getline)) {
                            $size += length $line;
                        }
                    };
                    $res->header('Content-Length' => $size);
                }
            } else {
                $res->status(404);
            }
        }
        when('PUT') {
            my %metadata;
            my $headers = $req->headers;
            foreach my $header (grep { /^x-sahara-/i } $headers->header_field_names) {
                my $value = $headers->header($header);
                if($header =~ /^x-sahara-(revision|name|is-deleted)$/i) {
                    $res->status(400);
                    $res->content_type('text/plain');
                    $res->body($header . ' is an invalid metadata header');
                    return $res->finalize;
                }
                $header =~ s/^x-sahara-//i;
                $metadata{$header} = $value;
            }
            my $current_revision = $metadata{'revision'} = $req->header('If-Match');
            my $revision         = eval {
                $self->storage->store_blob($user, $blob, $req->body, \%metadata);
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
                        my ( undef, $metadata ) = $self->storage->fetch_blob($user, $blob);
                        $metadata->{'revision'} = $revision;
                        $self->send_change_to_streams($user, $blob, $metadata);
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

            my $metadata;

            unless(defined $revision) {
                $res->status(400);
                $res->content_type('text/plain');
                $res->body('revision required');
            } else {
                if($env->{'sahara.streaming'}) {
                    ( undef, $metadata ) = $self->storage->fetch_blob($user, $blob);
                }
                $revision = eval {
                    $self->storage->delete_blob($user, $blob, $revision);
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
                        $res->header(ETag => $revision);

                        if($env->{'sahara.streaming'}) {
                            $metadata->{'is_deleted'} = 1;
                            delete $metadata->{'revision'};
                            $self->send_change_to_streams($user, $blob, $metadata);
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
    my ( $self ) = @_;

    my $store = $self->storage;

    builder {
        enable 'Sahara::Streaming';
        enable_if { $_[0]->{'REQUEST_URI'} =~ m!^/changes! } 'SetAccept',
            from => 'suffix', tolerant => 0, mapping => {
                json => 'application/json',
                xml  => 'application/xml',
                yml  => 'application/x-yaml',
                yaml => 'application/x-yaml',
            };
        mount '/changes' => builder {
            enable 'Options', allowed => [qw/GET/];
            enable 'Sahara::Auth', store => $store;
            sub {
                return $self->changes(@_);
            };
        };

        mount '/blobs' => builder {
            enable 'Options', allowed => [qw/GET HEAD PUT DELETE/];
            enable 'Sahara::Auth', store => $store;
            sub {
                return $self->blobs(@_);
            };
        };

        mount '/' => builder {
            enable_if { $_[0]->{'REQUEST_URI'} eq '/' } 'Options', allowed => [qw/HEAD/];
            sub {
                return $self->top_level(@_);
            };
        };
    };
}

1;

__END__

# ABSTRACT: Host daemon for Sahara Sync

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=head2 SaharaSync::Hostd->to_app

=head2 $hostd->to_app

Returns the PSGI application for this host daemon.

=head1 SEE ALSO

PSGI

=begin comment

=over

=item top_level

=item blobs

=item changes

=back

=end comment

=cut
