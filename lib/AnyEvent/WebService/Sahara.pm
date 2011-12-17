## no critic (RequireUseStrict)
package AnyEvent::WebService::Sahara;

## use critic (RequireUseStrict)
use strict;
use warnings;

use AnyEvent::HTTP;
use AnyEvent::WebService::Sahara::Error;
use Carp qw(croak);
use Guard qw(guard);
use List::MoreUtils qw(any);
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
    my $user          = $options{'user'}          || die "You must provide a user to " . __PACKAGE__ . "::new";
    my $password      = $options{'password'}      || die "You must provide a password to " . __PACKAGE__ . "::new";
    my $poll_interval = $options{'poll_interval'} || 15;

    return bless {
        url              => $url,
        user             => $user,
        password         => $password,
        poll_interval    => $poll_interval,
        change_guards    => {},
        inflight_changes => {},
        delayed_changes  => {},
        expected_changes => {},
    }, $class;
}

sub expect_change {
    my ( $self, $change ) = @_;

    my $name                           = $change->{'name'};
    $self->{'expected_changes'}{$name} = $change; ## what if $expected_changes->{$name} exists?
}

sub expecting_change {
    my ( $self, $change ) = @_;

    my $name = $change->{'name'};
    if(my $expected_change = delete $self->{'expected_changes'}{$name}) {
        if($expected_change->{'revision'} eq $change->{'revision'}) {
            return 1;
        }
    }
    return;
}

sub delay_change {
    my ( $self, $cb, $change ) = @_;

    my $name    = $change->{'name'};
    my $changes = $self->{'delayed_changes'};
    unless($changes->{$name}) {
        $changes->{$name} = [];
    }
    $changes = $changes->{$name};
    ## weaken
    push @$changes, [ $cb, $change ];
}

## delayed changes + change guards
sub run_delayed_changes {
    my ( $self, $name ) = @_;

    delete $self->{'inflight_changes'}{$name};
    my $changes = delete $self->{'delayed_changes'}{$name};
    return unless $changes;
    foreach my $pair (@$changes) {
        my ( $cb, $change ) = @$pair;
        $self->_handle_change($cb, $change);
    }
}

sub mark_in_flight {
    my ( $self, $name ) = @_;

    $self->{'inflight_changes'}{$name} = 1;
}

sub update_is_in_flight {
    my ( $self, $name ) = @_;

    return $self->{'inflight_changes'}{$name};
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

sub _check_for_error {
    my ( $self, $data, $headers ) = @_;

    my $status = $headers->{'Status'};

    if($status > 400) {
        my $reason = $headers->{'Reason'};
        $reason = $reasons{$status} if $status > 590 && exists $reasons{$status};

        return AnyEvent::WebService::Sahara::Error->new(
            code    => $status,
            message => $reason,
        );
    } elsif($status == 400) {
        # 400 errors are special, because we overload them
        # not ideal, I know.

        return AnyEvent::WebService::Sahara::Error->new(
            code    => $status,
            message => $data,
        );
    } else {
        return;
    }
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

    weaken $self;
    $handler = sub {
        my ( $data, $headers ) = @_;

        my $error = $self->_check_for_error($data, $headers);

        if($error) {
            $cb->($self, undef, $error);
        } else {
            $cb->($self, $prepare->($data, $headers));
        }

    };

    return http_request $method => $url, %$meta, $handler;
}

sub capabilities {
    my ( $self, $cb ) = @_;

    return $self->do_request(HEAD => '', sub {
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

    my $cb_wrapper = sub {
        my ( $self ) = @_;

        $self->run_delayed_changes($blob);

        return $cb->(@_);
    };

    $self->do_request(PUT => ['blobs', $blob], $meta, sub {
        my ( undef, $headers ) = @_;

        my $revision = $headers->{'etag'};

        $self->expect_change({
            name     => $blob,
            revision => $revision,
        });

        return $revision;
    }, $cb_wrapper);

    $self->mark_in_flight($blob);
}

sub delete_blob {
    my ( $self, $blob, $revision, $cb ) = @_;

    my $meta = {
        headers => {
            'If-Match' => $revision,
        },
    };

    my $cb_wrapper = sub {
        my ( $self ) = @_;

        $self->run_delayed_changes($blob);

        return $cb->(@_);
    };

    $self->do_request(DELETE => ['blobs', $blob], $meta, sub {
        my ( undef, $headers ) = @_;

        my $revision = $headers->{'etag'};

        $self->expect_change({
            name     => $blob,
            revision => $revision,
        });

        return $revision;
    }, $cb_wrapper);

    $self->mark_in_flight($blob);
}

sub _handle_change {
    my ( $self, $cb, $change ) = @_;

    my $name = $change->{'name'};

    if($self->update_is_in_flight($name)) {
        $self->delay_change($cb, $change);
        return;
    }
    if($self->expecting_change($change)) {
        return;
    }

    $cb->($self, $change);
}

sub _raw_streaming_request {
    my ( $self, $url, $meta, $cb, $on_eof ) = @_;

    my $h;

    weaken($self);
    my $guard = $self->do_request(GET => $url, $meta, sub {
        my $headers;
        ( $h, $headers ) = @_;

        my $reader = SaharaSync::Stream::Reader->for_mimetype($headers->{'content-type'});

        $reader->on_read_object(sub {
            my ( undef, $object ) = @_;

            $self->_handle_change($cb, $object);
        });

        $h->on_read(sub {
            my $chunk = $h->rbuf;
            $h->rbuf = '';

            $reader->feed($chunk);
        });

        $h->on_eof(sub {
            $reader->feed(undef);
            $h->destroy;
            undef $h;
            $on_eof->();
        });
    }, sub {
        my ( $self, $ok, $error ) = @_;

        $cb->(@_) unless $ok;
    });

    return ( $guard, \$h );
}

sub _streaming_changes {
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

    my ( $guard, $handle_ref, $handle_error );

    my $wrapped_cb;

    weaken($self);
    $handle_error = sub {
        my $timer;
        $timer = AnyEvent->timer(
            after => $self->{'poll_interval'},
            cb    => sub {
                # XXX check that we're still interested in a relationship
                #     with the host
                undef $timer;
                undef $$handle_ref;
                ( $guard, $handle_ref ) = $self->_raw_streaming_request($url,
                    $meta, $wrapped_cb, $handle_error);
            },
        );
    };

    do {
        my $handle_error_copy = $handle_error;
        weaken($handle_error_copy);
        $wrapped_cb = sub {
            my ( undef, $ok, $error ) = @_;

            if($ok || $error->is_fatal) {
                goto &$cb;
            } else {
                $handle_error_copy->();
            }
        };
    };

    ( $guard, $handle_ref ) = $self->_raw_streaming_request($url, $meta,
        $wrapped_cb, $handle_error);

    my $guards = $self->{'change_guards'};
    weaken($guards);
    $guards->{$guard} = guard {
        undef $$handle_ref;
        undef $guard;
    };

    if(defined wantarray) {
        return guard {
            delete $guards->{$guard} if $guards && $guard;
        };
    }
}

sub _non_streaming_changes {
    my ( $self, $since, $metadata, $cb ) = @_;

    my $meta = {
        headers => {
            'X-Sahara-Last-Sync' => $since,
        },
    };

    weaken($self);
    my $req_guard;
    my $timer_guard = AnyEvent->timer(
        interval => $self->{'poll_interval'},
        cb       => sub {
            ## if we get an error...what should happen?  should we keep
            ## throwing requests out there?

            my $url = 'changes';
            if($metadata && @$metadata) {
                $url = [ $url, { metadata => $metadata } ];
            }

            ## just because the timer is expired doesn't mean this is...
            $req_guard = $self->do_request(GET => $url, $meta, sub {
                my ( $body, $headers ) = @_;

                my $reader = SaharaSync::Stream::Reader->for_mimetype($headers->{'content-type'});

                $reader->on_read_object(sub {
                    my ( undef, $object ) = @_;

                    ## ???
                    $meta->{'headers'}{'X-Sahara-Last-Sync'} = $object->{'revision'};

                    $self->_handle_change($cb, $object);
                });

                $reader->feed($body);
                $reader->feed(undef);
            }, sub {
                my ( $self, $ok, $error ) = @_;

                $cb->(@_) unless $ok;
            });
        },
    );

    my $guards = $self->{'change_guards'};
    weaken($guards);
    $guards->{$timer_guard} = guard {
        undef $timer_guard;
        undef $req_guard;
    };

    if(defined wantarray) {
        return guard {
            delete $guards->{$timer_guard} if $guards && $timer_guard;
        };
    }
}

sub changes {
    my ( $self, $since, $metadata, $cb ) = @_;

    my $cond = AnyEvent->condvar;
    my $caps;
    my $error;

    $self->capabilities(sub {
        ( undef, $caps, $error ) = @_;

        $cond->send;
    });

    ## synchronous code alert!
    $cond->recv;

    unless($caps) {
        $cb->($self, undef, $error);
        return;
    }

    if(any { $_ eq 'streaming' } @$caps) {
        return $self->_streaming_changes($since, $metadata, $cb);
    } else {
        return $self->_non_streaming_changes($since, $metadata, $cb);
    }
}

1;

__END__

# ABSTRACT: Client library for Sahara Sync

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

All callbacks are passed a reference to the AnyEvent::WebService::Sahara
object calling them; other specified arguments are in \@_[1..$#$_].

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
