package AnyEvent::WebService::Sahara;

use strict;
use warnings;

our $VERSION = '0.01';

use AnyEvent::HTTP;
use Carp qw(croak);
use MIME::Base64 qw(encode_base64);
use URI;

use namespace::clean;

my $DEFAULT_SCHEME = 'http';

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
        url      => $url,
        user     => $user,
        password => $password,
    }, $class;
}

sub add_auth {
    my ( $self, $method, $url, $meta ) = @_;

    my $user     = $self->{'user'};
    my $password = $self->{'password'};
    my $header   = 'Basic ' . encode_base64($user . ':' . $password);
    my $headers  = $meta->{'headers'};
    unless($headers) {
        $headers = $meta->{'headers'} = {};
    }

    $headers->{'Authorization'} = $header;
}

# calling syntax: $self->do_request($method => @path, $opt_meta, $prepare, $cb)
sub do_request {
    my $self     = shift;
    my $method   = shift;
    my $cb       = pop;
    my $prepare  = pop;
    my $meta     = ref($_[$#_]) eq 'HASH' ? pop : {};
    my @segments = @_;

    my $url = $self->{'url'}->clone;
    $url->path_segments($url->path_segments, @segments);

    $self->add_auth($method, $url, $meta);

    my $handler;

    $handler = sub {
        my ( $data, $headers ) = @_;

        $cb->($prepare->($data, $headers));
    };

    http_request $method => $url, %$meta, $handler;
}

sub capabilities {
    my ( $self, $cb ) = @_;

    $self->do_request(GET => 'capabilities', sub {
        my ( $data, $headers ) = @_;

        return { map { $_ => 1 } split/,/, $data };
    }, $cb);
}

sub get_blob {
    my ( $self, $blob, $cb ) = @_;

    $self->do_request(GET => 'blobs', $blob, sub {
        my ( $data, $headers ) = @_;

        return $data;
    }, $cb);
}

sub put_blob {
    my ( $self, $blob, $contents, $cb ) = @_;

    my $method;
    my $meta = {};

    if(defined $contents) {
        $method = 'PUT';
        $meta->{'body'} = $contents;
    } else {
        $method = 'DELETE';
    }

    $self->do_request($method => 'blobs', $blob, $meta, sub {
        return 1; # if a bad status occurs, do_request handles it
    }, $cb);
}

sub changes {
    my ( $self, $cb ) = @_;
    ## should we automatically set up the timer?
}

1;

__END__

=head1 NAME

AnyEvent::WebService::Sahara

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

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

L<SaharaSync>

=cut
