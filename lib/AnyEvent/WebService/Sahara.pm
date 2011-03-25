package AnyEvent::WebService::Sahara;

use strict;
use warnings;

our $VERSION = '0.01';

use AnyEvent::HTTP;
use Carp qw(croak);
use Digest::MD5 qw(md5_hex);
use URI;

use namespace::clean;

my $DEFAULT_SCHEME = 'http';
my $HTTP_TOKEN     = qr/[^[:cntrl:] \t()<>@,;:\\"\/\[\]?={}]+/;

## handle multiple challenges
## handle Authentication-Info header
## ...which might appear in a trailer!

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

## handle case when values have \"
sub add_auth {
    my ( $self, $method, $url, $meta ) = @_;

    my $auth = $self->{'auth'};
    return unless $auth;

    my $uri          = $url->path_query;
    my $user         = $self->{'user'};
    my $password     = $self->{'password'};
    my $realm        = $auth->{'realm'};
    my $qop          = $auth->{'qop'} || '';
    my $nonce        = $auth->{'nonce'};
    my $nonce_count  = sprintf('%08x', $self->{'count'}++);
    my $client_nonce = '12345678'; ## hey

    my $ha1 = md5_hex(join(':', $user, $realm, $password));
    my $ha2;
    my $response;

    ## this can be a list of alternatives!
    if($qop eq 'auth-int') {
        ## hey
        croak "auth-int currently unsupported";
    } else {
        $ha2 = md5_hex(join(':', $method, $uri));
    }

    if($qop eq 'auth' || $qop eq 'auth-int') {
        $response = md5_hex(join(':', $ha1, $nonce, $nonce_count, $client_nonce, $qop, $ha2));
    } else {
        $response = md5_hex(join(':', $ha1, $nonce, $ha2));
    }
    ## don't add qop cnonce or nc in old-timey digest
    my $header = "Digest username=\"$user\", realm=\"$realm\", nonce=\"$nonce\", uri=\"$uri\", cnonce=\"$client_nonce\", nc=$nonce_count, qop=\"$qop\", response=\"$response\", algorithm=MD5";
    my $headers = $meta->{'headers'};
    unless($headers) {
        $headers = $meta->{'headers'} = {};
    }
    $headers->{'Authorization'} = $header;
}

sub has_auth {
    my ( $self ) = @_;

    return exists $self->{'auth'};
}

## rename
sub calculate_auth {
    my ( $self, $method, $url, $www_authenticate ) = @_;

    unless($www_authenticate =~ s/^Digest\s+//) {
        croak __PACKAGE__ . " operates on Digest authentication only";
    }
    my %attrs;
    while($www_authenticate =~ /(?<key>$HTTP_TOKEN)=(?:(?<value>$HTTP_TOKEN)|(?:"(?<value>[^"]+)"))/g) {
        $attrs{$+{'key'}} = $+{'value'};
    }
    unless($attrs{'algorithm'} eq 'MD5') {
        ## hey
        croak "Unsupported auth algorithm $attrs{'algorithm'}";
    }
    $self->{'auth'} = {
        count => 1,
        realm => $attrs{'realm'},
        qop   => $attrs{'qop'},
        nonce => $attrs{'nonce'},
    };
}

# calling syntax: $self->do_request($method => @path, $opt_meta, $prepare, $cb)
sub do_request {
    my $self     = shift;
    my $method   = shift;
    my $cb       = pop;
    my $prepare  = pop;
    my $meta     = ref($_[$#_]) eq 'HASH' ? $_[$#_] : {};
    my @segments = @_;

    my $url = $self->{'url'}->clone;
    $url->path_segments($url->path_segments, @segments);

    $self->add_auth($method, $url, $meta);

    my $handler;

    $handler = sub {
        my ( $data, $headers ) = @_;

        my $status = $headers->{'Status'};

        ## check data and headers and shit
        if($status == 401) {
            ## check staleness of nonce
            if($self->has_auth) {
                ## failure
            } else {
                $self->calculate_auth($method => $url, $headers->{'www-authenticate'});
                $self->add_auth($method, $url, $meta);
                http_request $method => $url, %$meta, $handler;
            }
        } else {
            $cb->($prepare->($data, $headers));
        }
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
