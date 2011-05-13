package SaharaSync::Hostd::Plugin::Store;

use Carp qw(croak);;
use SaharaSync::X::BadContext;
use SaharaSync::X::InvalidArgs;
use namespace::clean;

use Moose::Role;

our $VERSION = '0.01';

sub get {
    my ( $class ) = @_;

    unless($class eq __PACKAGE__) {
        croak 'Must be called as ' . __PACKAGE__ . '->get';
    }

    require SaharaSync::Hostd::Plugin::Store::DBIWithFS;
    return SaharaSync::Hostd::Plugin::Store::DBIWithFS->new(
        dsn => 'dbi:Pg:dbname=sahara',
    );
}

requires 'create_user';
requires 'remove_user';
requires 'load_user_info';
requires 'fetch_blob';
requires 'store_blob';
requires 'delete_blob';
requires 'fetch_changed_blobs';

around fetch_blob => sub {
    my $orig = shift;
    my $self = shift;

    unless(wantarray) {
        SaharaSync::X::BadContext->throw({
            context => (defined(wantarray) ? 'scalar' : 'void'),
        });
    }

    return $self->$orig(@_);
};

before store_blob => sub {
    my ( $self, $user, $name, $contents ) = @_;

    unless(UNIVERSAL::can($contents, 'read') || ref($contents) eq 'GLOB') {
        SaharaSync::X::InvalidArgs->throw({
            message => "store_blob contents must support the read operation",
        });
    }
};

before delete_blob => sub {
    my ( $self, $user, $name, $revision ) = @_;

    unless(defined $revision) {
        SaharaSync::X::InvalidArgs->throw({
            message => "Revision must be defined",
        });
    }
};

1;

__END__

=head1 NAME

SaharaSync::Hostd::Plugin::Store

=head1 VERSION

0.01

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 REQUIRED METHODS

=head2 $store->create_user($username, $password)

Creates a new user with username C<$username> and
password C<$password>.  Returns 1 if the user was
successfully created, or 0 otherwise.

=head2 $store->remove_user($username)

Deletes a user and all of his/her files.

=head2 $store->load_user_info($username)

Returns a hash reference containing the password
hash for C<$username> under the key 'password_hash'.

=head2 $store->fetch_blob($user, $blob)

Returns an L<IO::Handle> that contains the contents of
a blob named C<$blob> for user C<$user>.  If no such
blob exists, undef is returned.

=head2 $store->store_blob($user, $blob, $handle)

=head2 $store->store_blob($user, $blob)

Stores the contents of C<$handle> in a blob called C<$blob>
for user C<$user>.  C<$handle> is NOT necessarily an L<IO::Handle>;
the only interface it must implement is the read method
(see L<PSGI/"The Input Stream"> for details).  If C<$handle> is
undef or omitted, that blob is deleted.

=head2 $store->fetch_changed_blobs($user, $timestamp)

Returns an array of blob names that have changed since C<$timestamp>.
Duplicate entries may or may not be included.

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
