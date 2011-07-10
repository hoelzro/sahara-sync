## no critic (RequireUseStrict)
package AnyEvent::WebService::Sahara;

## use critic (RequireUseStrict)
use strict;
use warnings;

use AnyEvent::HTTP;
use Carp qw(croak);
use Guard qw(guard);
use MIME::Base64 qw(encode_base64);
use Scalar::Util qw(weaken);
use URI;
use URI::QueryParam;

use SaharaSync::Stream::Reader;

use namespace::clean;

my $DEFAULT_SCHEME = 'http';

# override has to ensure consistency among different operating systems
my %reasons = (
    595 => 'Connection refused',
);

sub new {
    my ( $class, %options ) = @_;

    my $url;

    if(exists $options{'url'}) {
        $url = URI->new($options{'url'});
        unless($url->scheme eq 'http' || $url->scheme eq 'https') {
            croak "Provided URL must have either http:// or https:// scheme";
        }
    } else {
        my ( $host, $port, $scheme ) = @options{qw/host port scheme/};

        $scheme = $DEFAULT_SCHEME unless $scheme;
        unless($host && $port) {
            croak "You must provide a url or host/port option to " . __PACKAGE__ . "::new"
        }
        unless($scheme eq 'http' || $scheme eq 'https') {
            croak "Scheme must be either http or https";
        }
        $url = URI->new("$scheme://$host:$port");
    }
    my $user     = $options{'user'}     || die "You must provide a user to " . __PACKAGE__ . "::new";
    my $password = $options{'password'} || die "You must provide a password to " . __PACKAGE__ . "::new";

    return bless {
        url           => $url,
        user          => $user,
        password      => $password,
        change_guards => {},
    }, $class;
}

sub add_auth {
    my ( $self, $method, $url, $meta ) = @_;

    my $user     = $self->{'user'};
    my $password = $self->{'password'};
    my $header   = 'Basic ' . encode_base64($user . ':' . $password, '');
    my $headers  = $meta->{'headers'};
    unless($headers) {
        $headers = $meta->{'headers'} = {};
    }

    $headers->{'Authorization'} = $header;
}

# calling syntax: $self->do_request($method => @path, $opt_meta, $prepare, $cb)
sub do_request {
    my ( $self, $method, $segments, $meta, $prepare, $cb );

    if(@_ == 5) {
        ( $self, $method, $segments, $prepare, $cb, $meta ) = (@_, {});
    } else {
        ( $self, $method, $segments, $meta, $prepare, $cb ) = @_;
    }
    $segments = [ $segments ] unless ref($segments);

    my $params;
    if(ref($segments->[$#$segments]) eq 'HASH') {
        $params = pop @$segments;
    }

    my $url = $self->{'url'}->clone;
    $url->path_segments($url->path_segments, @$segments);
    if($params) {
        foreach my $k (keys %$params) {
            my $v = $params->{$k};

            if(ref $v) {
                $url->query_param($k, @$v);
            } else {
                $url->query_param($k, $v);
            }
        }
    }

    $self->add_auth($method, $url, $meta);

    my $handler;

    $handler = sub {
        my ( $data, $headers ) = @_;

        my $status = $headers->{'Status'};

        if($status > 400) {
            my $reason = $headers->{'Reason'};
            $reason = $reasons{$status} if $status > 590 && exists $reasons{$status};
            $cb->(undef, $reason);
        } elsif($status == 400) {
            # 400 errors are special, because we overload them
            # not ideal, I know.

            $cb->(undef, $data);
        } else {
            $cb->($prepare->($data, $headers));
        }
    };

    return http_request $method => $url, %$meta, $handler;
}

sub capabilities {
    my ( $self, $cb ) = @_;

    $self->do_request(HEAD => '', sub {
        my ( $data, $headers ) = @_;

        my $capabilities = $headers->{'x-sahara-capabilities'};

        return [ split /\s*,\s*/, $capabilities ];
    }, $cb);
}

sub get_blob {
    my ( $self, $blob, $cb ) = @_;

    my $meta = {
        want_body_handle => 1,
    };

    $self->do_request(GET => ['blobs', $blob], $meta, sub {
        my ( $h, $headers ) = @_;

        my %metadata;

        my $revision = $headers->{'etag'};
        if($revision) {
            $metadata{'revision'} = $revision;
        }

        foreach my $k (keys %$headers) {
            my $v = $headers->{$k};

            if($k =~ s/^x-sahara-//i) {
                $metadata{$k} = $v;
            }
        }

        return $h, \%metadata;
    }, $cb);
}

sub put_blob {
    my ( $self, $blob, $contents, $metadata, $cb ) = @_;

    $metadata ||= {};

    my $revision = delete $metadata->{'revision'};

    ## inefficient
    $contents = do {
        local $/;
        <$contents>;
    };

    my $meta = {
        body => $contents,
    };

    if(defined $revision) {
        my $headers = $meta->{'headers'} = {};
        $headers->{'If-Match'} = $revision;
    }

    if(%$metadata) {
        my $headers = $meta->{'headers'} || {};
        $meta->{'headers'} = $headers;

        foreach my $k (keys %$metadata) {
            my $v = $metadata->{$k};

            $k =~ s/\b([a-z])/uc $1/ge;

            $headers->{"X-Sahara-$k"} = $v;
        }
    }

    $self->do_request(PUT => ['blobs', $blob], $meta, sub {
        my ( undef, $headers ) = @_;

        return $headers->{'etag'};
    }, $cb);
}

sub delete_blob {
    my ( $self, $blob, $revision, $cb ) = @_;

    my $meta = {
        headers => {
            'If-Match' => $revision,
        },
    };

    $self->do_request(DELETE => ['blobs', $blob], $meta, sub {
        my ( undef, $headers ) = @_;

        return $headers->{'etag'};
    }, $cb);
}

sub changes {
    my ( $self, $since, $metadata, $cb ) = @_;

    my $meta = {
        want_body_handle => 1,
        headers => {
            'X-Sahara-Last-Sync' => $since,
        },
    };

    my $url = 'changes';
    if($metadata && @$metadata) {
        $url = [ $url, { metadata => $metadata } ];
    }

    my $h;

    my $guard = $self->do_request(GET => $url, $meta, sub {
        my $headers;
        ( $h, $headers ) = @_;

        my $reader = SaharaSync::Stream::Reader->for_mimetype($headers->{'content-type'});

        $reader->on_read_object(sub {
            my ( undef, $object ) = @_;

            $cb->($object);
        });

        $h->on_read(sub {
            my $chunk = $h->rbuf;
            $h->rbuf = '';

            $reader->feed($chunk);
        });

        $h->on_eof(sub {
            $reader->feed(undef);
            undef $h;
        });
    }, sub {
        my ( $ok, $error ) = @_;

        $cb->(@_) unless $ok;
    });

    my $guards = $self->{'change_guards'};
    weaken($guards);
    $guards->{$guard} = guard {
        undef $h;
        undef $guard;
    };

    if(defined wantarray) {
        return guard {
            delete $guards->{$guard} if $guards && $guard;
        };
    }
}

1;

__END__

# ABSTRACT: Client library for Sahara Sync

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head2 AnyEvent::WebService::Sahara->new(%options)

Creates a new AnyEvent::WebService::Sahara object.  The parameters C<user> and
C<password> are required.  Also, you must specify either the C<url> parameter
or the C<host>, C<port>, or C<scheme> parameters.

=head2 $client->capabilities($callback)

Fetches the capabilties of the Sahara host the client is connected to, and
passes them to C<$callback> as hash reference.  The keys of the hash reference
are the capabilities; the values are just truthy values.

=head2 $client->get_blob($blob, $callback)

Gets the contents of the blob C<$blob> and pass them to C<$callback>.

=head2 $client->put_blob($blob, $contents, $callback)

Stores C<$contents> as the contents of C<$blob> and passes
the result of the operation to C<$callback>.

=head2 $client->changes($callback)

Sets up a change listener and pass each change object to C<$callback>.

=begin comment

=over

=item add_auth

=item do_request

=back

=end comment

=cut
