package Test::Sahara;

use strict;
use warnings;
use FindBin;

use lib "$FindBin::Bin/../lib";

use HTTP::Request ();
use MIME::Base64 ();
use Plack::Test ();
use SaharaSync::Hostd ();
use Test::More ();

our $VERSION = '0.01';

sub test_host {
    my ( $cb ) = @_;

    my $app = SaharaSync::Hostd->to_app;

    return Plack::Test::test_psgi $app, $cb;
}

sub REQUEST {
    my ( $method, $path, %headers ) = @_;

    my $content = delete $headers{'Content'};

    my $req = HTTP::Request->new($method, $path);
    foreach my $k (keys %headers) {
        $req->header($k => $headers{$k});
    }
    if(defined $content) {
        $req->content($content);
    }

    return $req;
}

sub REQUEST_AUTHD {
    my ( $method, $path, %headers ) = @_;

    $headers{'Authorization'} = 'Basic ' . MIME::Base64::encode_base64('test:abc123');

    return REQUEST($method, $path, %headers);
}

my @methods = qw(GET POST PUT DELETE HEAD OPTIONS);

foreach my $method (@methods) {
    no strict 'refs';

    *{$method} = sub {
        return REQUEST($method, @_);
    };

    *{$method . '_AUTHD'} = sub {
        return REQUEST_AUTHD($method, @_);
    };
}

sub import {
    my ( $class, @args ) = @_;

    my %options = map { $_ => 1 } grep { /^:/ } @args;
    @args       = grep { ! /^:/ } @args;

    my $dest = caller;

    no strict 'refs';

    *{$dest . '::test_host'} = \&test_host;
    foreach my $sym (@Test::More::EXPORT) {
        *{$dest . '::' . $sym} = \&{'Test::More::' . $sym};
    }

    if($options{':methods'}) {
        foreach my $method (@methods) {
            *{$dest . '::' . $method}            = \&{$method};
            *{$dest . '::' . $method . '_AUTHD'} = \&{$method . '_AUTHD'};
        }
    }

    Test::More::plan @args if @args;
}

1;

__END__

=head1 NAME

Test::Sahara

=head1 VERSION

0.01

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=head1 AUTHOR

Rob Hoelz, C<< rob at hoelz.ro >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-SaharaSync at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=SaharaSync>. I will
be notified, and then you'll automatically be notified of progress on your bug as I make changes.

=head1 COPYRIGHT & LICENSE

Copyright 2011 Rob Hoelz.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

=cut
