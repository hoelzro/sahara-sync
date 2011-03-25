package SaharaSync::Hostd::Plugin::Store;

use Carp qw(croak);;
use namespace::clean;

use Moose::Role;

our $VERSION = '0.01';

sub get {
    my ( $class ) = @_;

    unless($class eq __PACKAGE__) {
        croak 'Must be called as ' . __PACKAGE__ . '->get';
    }

    require SaharaSync::Hostd::Plugin::Store::DBIWithFS;
    return SaharaSync::Hostd::Plugin::Store::DBIWithFS->new;
}

requires 'load_user_info';
requires 'fetch_blob';
requires 'store_blob';
requires 'fetch_changed_blobs';

1;

__END__

=head1 NAME

SaharaSync::Hostd::Plugin::Store

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

L<SaharaSync>, L<SaharaSync::Hostd>

=cut
