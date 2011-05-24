package SaharaSync::Hostd::Plugin::Store::DBIWithFS;

use Carp qw(croak);
use Digest::SHA;
use DBI;
use File::Path qw(make_path remove_tree);
use File::Spec;
use IO::File;
use MIME::Base64 qw(encode_base64);

use SaharaSync::X::BadUser;
use SaharaSync::X::BadRevision;
use SaharaSync::X::InvalidArgs;
use SaharaSync::X::NoSuchBlob;

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

sub _blob_to_disk_name {
    my ( $self, $blob_name ) = @_;

    return encode_base64($blob_name, '');
}

sub _save_blob_to_disk {
    my ( $self, $user, $blob, $revision, $src ) = @_;

    my $disk_name      = $self->_blob_to_disk_name($blob);
    my $path           = File::Spec->catfile($self->fs_storage_path, $user, $disk_name);
    my ( undef, $dir ) = File::Spec->splitpath($path);
    my $buf            = '';
    my $n;

    make_path $dir;
    my $digest = Digest::SHA->new(256);
    $digest->add($blob);
    $digest->add($revision);
    if(defined $src) {
        $digest->add("\1");

        my $f = IO::File->new($path, 'w');
        croak "Unable to open '$path': $!" unless $f;

        do {
            $n = $src->read($buf, 1024);
            croak "read failed: $!" unless defined $n;
            if($n) {
                $digest->add($buf);
                $f->syswrite($buf, $n) || croak "write failed: $!";
            }
        } while $n;
        $f->close;
    } else {
        $digest->add("\0");

        unlink($path) || die "Unable to delete '$path': $!";
    }

    return $digest->hexdigest;
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
        SaharaSync::X::BadUser->throw({
            username => $user,
        });
    }

    return $user_id;
}

sub create_user {
    my ( $self, $username, $password ) = @_;

    my $dbh = $self->dbh;
    my ( $exists ) = $dbh->selectrow_array(<<SQL, undef, $username);
SELECT COUNT(1) FROM users
WHERE username = ?
SQL
    if($exists) {
        SaharaSync::X::BadUser->throw({
            username => $username,
        });
    } else {
        $dbh->do(<<SQL, undef, $username, $password);
INSERT INTO users (username, password) VALUES (?, ?)
SQL
        return 1;
    }
}

sub remove_user {
    my ( $self, $username ) = @_;

    my $dbh = $self->dbh;
    my $path = File::Spec->catdir($self->fs_storage_path, $username);

    remove_tree $path;

    my $exists = $dbh->do(<<SQL, undef, $username) != 0;
DELETE FROM users WHERE username = ?
SQL
    if($exists) {
        return 1;
    } else {
        SaharaSync::X::BadUser->throw({
            username => $username,
        });
    }
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
SELECT u.username IS NOT NULL, b.blob_name IS NOT NULL, b.revision
FROM users AS u
LEFT JOIN blobs AS b
ON  b.owner = u.user_id
AND b.blob_name = ?
AND b.is_deleted = FALSE
WHERE u.username = ?
SQL

    $sth->execute($blob, $user);

    my ( $user_exists, $file_exists, $revision ) = $sth->fetchrow_array;

    unless($user_exists) {
        SaharaSync::X::BadUser->throw({
            username => $user,
        });
    }

    if($file_exists) {
        my $disk_name = $self->_blob_to_disk_name($blob);
        my $path      = File::Spec->catfile($self->fs_storage_path, $user, $disk_name);
        my $handle    = IO::File->new($path, 'r');
        unless($handle) {
            croak "Unable to open '$path': $!";
        }
        return ( $handle, $revision );
    } else {
        return;
    }
}

sub store_blob {
    my ( $self, $user, $blob, $handle, $revision ) = @_;

    my $user_id = $self->_get_user_id($user);
    my $dbh     = $self->dbh;

    my ( $is_deleted, $current_revision ) =
        $dbh->selectrow_array(<<SQL, undef, $user_id, $blob);
SELECT is_deleted, revision FROM blobs
WHERE owner     = ?
AND   blob_name = ?
SQL
    if(defined $current_revision) {
        if($is_deleted) {
            if(defined $revision) {
                SaharaSync::X::InvalidArgs->throw({
                    message => "You can't provide a revision when creating a new blob",
                });
            }
            $revision = $self->_save_blob_to_disk($user, $blob, $current_revision, $handle);
        } else {
            unless(defined $revision) {
                SaharaSync::X::InvalidArgs->throw({
                    message => "Revision required",
                });
            }
            unless($revision eq $current_revision) {
                return undef;
            }
            $revision = $self->_save_blob_to_disk($user, $blob, $revision, $handle);
        }
        $dbh->begin_work;
        $dbh->do(<<SQL, undef, $revision, $user_id, $blob);
UPDATE blobs
SET is_deleted = FALSE,
    revision   = ?
WHERE owner      = ?
AND   blob_name  = ?
SQL
        $dbh->do(<<SQL, undef, $user_id, $revision, $blob);
INSERT INTO revision_log (user_id, blob_revision, blob_name) VALUES(?, ?, ?)
SQL
        $dbh->commit;
    } else {
        if(defined $revision) {
            SaharaSync::X::InvalidArgs->throw({
                message => "You can't provide a revision when creating a new blob",
            });
        }
        $revision = $self->_save_blob_to_disk($user, $blob, '', $handle);
        $dbh->begin_work;
        $dbh->do(<<SQL, undef, $user_id, $blob, $revision);
INSERT INTO blobs (owner, blob_name, revision) VALUES (?, ?, ?)
SQL
        $dbh->do(<<SQL, undef, $user_id, $revision, $blob);
INSERT INTO revision_log (user_id, blob_revision, blob_name) VALUES(?, ?, ?)
SQL
        $dbh->commit;
    }

    return $revision;
}

sub delete_blob {
    my ( $self, $user, $blob, $revision ) = @_;

    my $user_id = $self->_get_user_id($user);
    my $dbh     = $self->dbh;

    my ( $current_revision ) = $dbh->selectrow_array(<<SQL, undef, $user_id, $blob);
SELECT revision FROM blobs
WHERE owner      = ?
AND   blob_name  = ?
AND   is_deleted = FALSE
SQL

    unless(defined $current_revision) {
        SaharaSync::X::NoSuchBlob->throw({
            blob => $blob,
        });
    }
    unless($revision eq $current_revision) {
        return undef;
    }

    $revision = $self->_save_blob_to_disk($user, $blob, $revision);

    $dbh->begin_work;
    $dbh->do(<<SQL, undef, $revision, $user_id, $blob);
UPDATE blobs
SET is_deleted = TRUE,
    revision   = ?
WHERE owner      = ?
AND   blob_name  = ?
AND   is_deleted = FALSE
SQL
    $dbh->do(<<SQL, undef, $user_id, $revision, $blob);
INSERT INTO revision_log (user_id, blob_revision, blob_name) VALUES(?, ?, ?)
SQL
    $dbh->commit;

    return $revision;
}

sub fetch_changed_blobs {
    my ( $self, $user, $last_revision ) = @_;

    my $dbh     = $self->dbh;
    my $user_id = $self->_get_user_id($user);
    my $sth;

    if(defined $last_revision) {
        my ( $rev_id ) = $dbh->selectrow_array(<<SQL, undef, $user_id, $last_revision);
SELECT revision_id FROM revision_log
WHERE user_id       = ?
AND   blob_revision = ?
SQL

        unless(defined $rev_id) {
            SaharaSync::X::BadRevision->throw({
                revision => $last_revision,
            });
        }

        $sth = $dbh->prepare(<<SQL);
SELECT b.is_deleted, r.blob_name FROM revision_log AS r
INNER JOIN blobs AS b
ON  r.blob_name = b.blob_name
AND r.user_id   = b.owner
WHERE r.user_id     = ?
AND   r.revision_id > ?
SQL

        $sth->execute($user_id, $rev_id);
    } else {
        $sth = $dbh->prepare(<<SQL);
SELECT b.is_deleted, r.blob_name FROM revision_log AS r
INNER JOIN blobs AS b
ON  r.blob_name = b.blob_name
AND r.user_id   = b.owner
WHERE r.user_id = ?
SQL
        $sth->execute($user_id);
    }

    my %blobs;

    ## we need to include deleted data eventually
    while(my ( undef, $blob ) = $sth->fetchrow_array) {
        $blobs{$blob} = 1;
    }

    return keys %blobs;
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
