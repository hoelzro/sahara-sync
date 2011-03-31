package Test::Sahara;

use strict;
use warnings;
use FindBin;

use lib "$FindBin::Bin/../lib";

use Plack::Test ();
use SaharaSync::Hostd ();
use Test::More ();

our $VERSION = '0.01';

sub test_host {
    my ( $cb ) = @_;

    my $app = SaharaSync::Hostd->to_app;

    return Plack::Test::test_psgi $app, $cb;
}

sub import {
    my ( $class, @args ) = @_;

    my $dest = caller;

    no strict 'refs';

    *{$dest . '::test_host'} = \&test_host;
    foreach my $sym (@Test::More::EXPORT) {
        *{$dest . '::' . $sym} = \&{'Test::More::' . $sym};
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