package SaharaSync::X::BadContext;

use Moose::Util::TypeConstraints qw(enum);
use namespace::clean;

use Moose;
with 'Throwable';

has context => (
    is  => 'ro',
    isa => enum [qw/void scalar/],
);

1;

__END__

=head1 NAME

SaharaSync::X::BadContext

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

L<SaharaSync>

=cut
