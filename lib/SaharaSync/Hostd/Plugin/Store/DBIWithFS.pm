package SaharaSync::Hostd::Plugin::Store::DBIWithFS;

use Carp qw(croak);
use DBI;
use File::Path qw(make_path remove_tree);
use File::Spec;
use IO::File;

use namespace::clean;

use Moose;

with 'SaharaSync::Hostd::Plugin::Store';

our $VERSION = '0.01';

has dbh => (
    is       => 'ro',
    required => 1,
);

has fs_storage_path => (
    is      => 'ro',
    isa     => 'Str',
    default => '/tmp/sahara/',
);

sub BUILDARGS {
    my ( $class, %args ) = @_;

    my $dsn      = delete $args{'dsn'};
    my $username = delete $args{'username'} || '';
    my $password = delete $args{'password'} || '';

    if(defined $dsn) {
        $args{'dbh'} = DBI->connect($dsn, $username, $password);
    }

    return \%args;
}

sub _dump_to_file {
    my ( $self, $dest, $src ) = @_;

    my $buf = '';
    my $n;

    my $f = IO::File->new($dest, 'w');
    croak "Unable to open '$dest': $!" unless $f;

    do {
        $n = $src->read($buf, 1024);
        croak "read failed: $!" unless defined $n;
        $f->syswrite($buf, $n) || croak "write failed: $!" if $n;
    } while $n;

    $f->close;
}

sub _get_user_id {
    my ( $self, $user ) = @_;

    my $dbh = $self->dbh;
    my $sth = $dbh->prepare(<<SQL);
SELECT user_id FROM users WHERE username = ?
SQL

    $sth->execute($user);
    my ( $user_id ) = $sth->fetchrow_array;
    unless(defined $user_id) {
        croak "No user '$user' found!";
    }

    return $user_id;
}

sub _put_blob {
    my ( $self, $user, $blob, $handle ) = @_;

    my $path    = File::Spec->catfile($self->fs_storage_path, $user, $blob);
    my $user_id = $self->_get_user_id($user);
    my $dbh     = $self->dbh;

    $dbh->begin_work;

    my ( $row_exists, $is_deleted ) = $dbh->selectrow_array(<<SQL, undef, $user_id, $blob);
SELECT 1, is_deleted FROM blobs
WHERE owner     = ?
AND   blob_name = ?
SQL

    my $exists = $row_exists && !$is_deleted;

    if($row_exists) {
        $dbh->do(<<SQL, undef, $user_id, $blob);
UPDATE blobs
SET modified_time = CURRENT_TIMESTAMP,
    is_deleted    = FALSE
WHERE owner      = ?
AND   blob_name  = ?
SQL
    } else {
        $dbh->do(<<SQL, undef, $user_id, $blob);
INSERT INTO blobs (owner, blob_name) VALUES (?, ?)
SQL
    }

    my ( undef, $dir ) = File::Spec->splitpath($path);
    eval {
        make_path $dir;
        $self->_dump_to_file($path, $handle);
    };
    if($@) {
        $dbh->rollback;
        die;
    }
    $dbh->commit;
    return $exists;
}

sub _delete_blob {
    my ( $self, $user, $blob ) = @_;

    my $path    = File::Spec->catfile($self->fs_storage_path, $user, $blob);
    my $user_id = $self->_get_user_id($user);
    my $dbh     = $self->dbh;

    $dbh->begin_work;
## HELLO non-portable SQL!
    my $sth = $dbh->prepare(<<SQL);
UPDATE blobs
SET modified_time = CURRENT_TIMESTAMP, 
    is_deleted    = TRUE
WHERE owner     = ?
AND   blob_name = ?
AND   is_deleted = FALSE
SQL
    my $exists = $sth->execute($user_id, $blob) != 0;
    if($exists) {
        unless(unlink $path) {
            my $error = $!;
            $dbh->rollback;
            croak "Unable to delete '$path': $error";
        }
    }
    $dbh->commit;
    return $exists != 0;
}

sub create_user {
    my ( $self, $username, $password ) = @_;

    my $dbh = $self->dbh;
    my ( $exists ) = $dbh->selectrow_array(<<SQL, undef, $username);
SELECT COUNT(1) FROM users
WHERE username = ?
SQL
    if($exists) {
        return 0;
    } else {
        $dbh->do(<<SQL, undef, $username, $password);
INSERT INTO users (username, password) VALUES (?, ?)
SQL
    }
}

sub remove_user {
    my ( $self, $username ) = @_;

    my $dbh = $self->dbh;
    my $path = File::Spec->catdir($self->fs_storage_path, $username);

    remove_tree $path;

    my $exists = $dbh->do(<<SQL, undef, $username);
DELETE FROM users WHERE username = ?
SQL
    return $exists != 0;
}

sub load_user_info {
    my ( $self, $username ) = @_;

    my $dbh = $self->dbh;
    my $sth = $dbh->prepare(<<SQL);
SELECT password FROM users WHERE username = ?
SQL
    $sth->execute($username);
    if(my ( $password ) = $sth->fetchrow_array) {
        return {
            username => $username,
            password => $password,
        };
    }
    return;
}

sub fetch_blob {
    my ( $self, $user, $blob ) = @_;

    my $dbh = $self->dbh;
## HELLO non-portable SQL!
    my $sth = $dbh->prepare(<<SQL);
SELECT u.username IS NOT NULL, b.blob_name IS NOT NULL FROM users AS u
LEFT JOIN blobs AS b
ON  b.owner = u.user_id
AND b.blob_name = ?
AND b.is_deleted = FALSE
WHERE u.username = ?
SQL

    $sth->execute($blob, $user);

    my ( $user_exists, $file_exists ) = $sth->fetchrow_array;

    unless($user_exists) {
        croak "No user '$user' found!";
    }

    if($file_exists) {
        my $path = File::Spec->catfile($self->fs_storage_path, $user, $blob);
        my $handle = IO::File->new($path, 'r');
        unless($handle) {
            croak "Unable to open '$path': $!";
        }
        return $handle;
    } else {
        return;
    }
}

sub store_blob {
    my ( $self, $user, $blob, $handle ) = @_;

    if(defined $handle) {
        return $self->_put_blob($user, $blob, $handle);
    } else {
        return $self->_delete_blob($user, $blob);
    }
}

sub fetch_changed_blobs {
    my ( $self, $user, $last_sync ) = @_;

    my $dbh = $self->dbh;
    my $sth = $dbh->prepare(<<SQL);
SELECT b.is_deleted, b.blob_name FROM blobs AS b
INNER JOIN users AS u ON u.user_id = b.owner
WHERE u.username       = ?
AND   EXTRACT(EPOCH FROM b.modified_time) >= ?
SQL

    $sth->execute($user, $last_sync);
    my @blobs;
    ## we need to include deleted data eventually
    while(my ( undef, $blob ) = $sth->fetchrow_array) {
        push @blobs, $blob;
    }
    unless(@blobs) {
        my ( $exists ) = $dbh->selectrow_array(<<SQL, undef, $user);
SELECT COUNT(1) FROM users WHERE username = ?
SQL
        croak "No such user '$user'" unless $exists;
    }

    return @blobs;
}

1;

__END__

=head1 NAME

SaharaSync::Hostd::Plugin::Store::DBIWithFS

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

L<SaharaSync>, L<SaharaSync::Hostd>, L<SaharaSync::Hostd::Plugin::Store>

=cut
