package SaharaSync::Hostd;

use strict;
use warnings;
use feature 'switch';

our $VERSION = '0.01';

use Plack::Builder;
use Plack::Request;

## NOTE: I should probably just refactor the common functionality of
## the standalone daemon out, and write a separate script that handles
## polling requests for CGI and whatnot, and another separate script
## for the standalone daemon that implements the PSGI spec instead of
## relying on Twiggy.  That way, I don't have to resort to voodoo
## with Twiggy's handles.

## probably replace this with a plugin loader module some day
use SaharaSync::Hostd::Plugin::Store;

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
        $res->status(204);
        $res->header('X-Sahara-Capabilities' => $env->{'psgi.nonblocking'} ? 'streaming' : '');
    };
    $res->finalize;
}

sub changes {
    my ( $env ) = @_;

    my $req       = Plack::Request->new($env);
    my $last_sync = $req->header('X-Sahara-Last-Sync');
    my $user      = $req->user;
    my @blobs     = $store->fetch_changed_blobs($user, $last_sync);

    if($env->{'psgi.nonblocking'}) {
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
            my $handle = $store->fetch_blob($user, $blob);

            if(defined $handle) {
                $res->status(200);
                $res->content_type('application/octet-stream');
                $res->body($handle);
            } else {
                $res->status(404);
                $res->content_type('text/plain');
                $res->body('not found');
            }
        }
        when('PUT') {
            my $existed = $store->store_blob($user, $blob, $req->body);

            if($existed) {
                $res->status(200);
            } else {
                $res->status(201);
            }
            $res->content_type('text/plain');
            $res->body('ok');

            if($env->{'psgi.nonblocking'}) {
                my $conns = $connections{$user};
                if($conns) {
                    foreach my $writer (@$conns) {
                        $writer->write("$blob\n");
                    }
                }
            }
        }
        when('DELETE') {
            my $exists = $store->store_blob($user, $blob, undef);

            if($exists) {
                $res->status(200);
                $res->content_type('text/plain');
                $res->body('ok');

                if($env->{'psgi.nonblocking'}) {
                    my $conns = $connections{$user};
                    if($conns) {
                        foreach my $writer (@$conns) {
                            $writer->write("$blob\n");
                        }
                    }
                }
            } else {
                $res->status(404);
                $res->content_type('text/plain');
                $res->body('not found');
            }
       }
    }
    $res->finalize;
}

sub to_app {
    builder {
        mount '/changes' => builder {
            enable 'Options', allowed => [qw/GET/];
            enable 'Sahara::Auth', store => $store;
            \&changes;
        };

        mount '/blobs' => builder {
            enable 'Options', allowed => [qw/GET PUT DELETE/];
            enable 'Sahara::Auth', store => $store;
            \&blobs;
        };

        mount '/' => builder {
            enable 'Options', allowed => [qw/HEAD/];
            \&top_level;
        };
    }->to_app;
}

1;

__END__

=head1 NAME

SaharaSync::Hostd

=head1 VERSION

0.01

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=head1 AUTHOR

Rob Hoelz, C<< rob at hoelz.ro >>

=head1 BUGS

=head1 COPYRIGHT & LICENSE

Copyright 2011 Rob Hoelz.

This file is part of Sahara Sync.

Sahara Sync is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Sahara Sync is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with Sahara Sync.  If not, see <http://www.gnu.org/licenses/>.

=head1 SEE ALSO

L<SaharaSync>

=cut
