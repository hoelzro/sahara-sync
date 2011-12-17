## no critic (RequireUseStrict)
package SaharaSync::Hostd::Plugin::Store::DBIWithFS;

## use critic (RequireUseStrict)
use Carp qw(croak);
use Carp::Clan qw(^SaharaSync::Hostd::Plugin::Store ^Class::MOP::Method);
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

has dbh => (
    is       => 'ro',
    required => 1,
);

has storage_path => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has _statements => (
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_statements',
);

sub BUILDARGS {
    my ( $class, %args ) = @_;

    my $dsn      = delete $args{'dsn'};
    my $username = delete $args{'username'} || '';
    my $password = delete $args{'password'} || '';

    if(defined $dsn) {
        $args{'dbh'} = DBI->connect($dsn, $username, $password, {
            pg_server_prepare    => 1,
            pg_prepare_now       => 1,
            mysql_server_prepare => 1,
        });
    }
    
    my $dbh = $args{'dbh'};
    if($dbh->{'Driver'}{'Name'} eq 'SQLite') {
        $dbh->do('PRAGMA foreign_keys = ON');
        $dbh->do('PRAGMA journal_mode = WAL');
        if($ENV{'TAP_VERSION'}) { # silly optimization for testing
            $dbh->do('PRAGMA synchronous = OFF');
        }
    }

    return \%args;
}

sub _build_statements {
    my ( $self ) = @_;

    my $dbh = $self->dbh;

    my %statements = (
        get_user_id         => 'SELECT user_id FROM users WHERE username = ? LIMIT 1',
        insert_user         => 'INSERT INTO users (username, password) VALUES (?, ?)',
        remove_user         => 'DELETE FROM users WHERE username = ?',
        get_password        => 'SELECT password FROM users WHERE username = ? LIMIT 1',
        fetch_info_for_blob => <<'END_SQL',
SELECT u.username IS NOT NULL, b.blob_id, b.revision
FROM users AS u
LEFT JOIN blobs AS b
ON  b.user_id   = u.user_id
AND b.blob_name = ?
AND b.is_deleted = 0
WHERE u.username = ?
LIMIT 1
END_SQL
        metadata_for_blob      => 'SELECT meta_key, meta_value FROM metadata WHERE blob_id = ?',
        revision_info_for_blob => <<'END_SQL',
SELECT is_deleted, blob_id, revision FROM blobs
WHERE user_id   = ?
AND   blob_name = ?
LIMIT 1
END_SQL
        update_revision => <<'END_SQL',
UPDATE blobs
SET is_deleted = 0,
    revision   = ?
WHERE blob_id = ?
END_SQL
        insert_blob     => 'INSERT INTO blobs (user_id, blob_name, revision) VALUES (?, ?, ?)',
        update_revlog   => 'INSERT INTO revision_log (blob_id, blob_revision) VALUES(?, ?)',
        insert_metadata => 'INSERT INTO metadata (blob_id, meta_key, meta_value) VALUES (?, ?, ?)',

        revision_info_for_existing_blob => <<'END_SQL',
SELECT blob_id, revision FROM blobs
WHERE user_id    = ?
AND   blob_name  = ?
AND   is_deleted = 0
LIMIT 1
END_SQL
        mark_blob_deleted => <<'END_SQL',
UPDATE blobs
SET is_deleted = 1,
    revision   = ?
WHERE user_id    = ?
AND   blob_name  = ?
AND   is_deleted = 0
END_SQL
        delete_metadata => <<'END_SQL',
DELETE FROM metadata WHERE blob_id = ?
END_SQL
        get_revision_id => <<'END_SQL',
SELECT r.revision_id FROM revision_log AS r
INNER JOIN blobs AS b
ON b.blob_id = r.blob_id
WHERE b.user_id       = ?
AND   r.blob_revision = ?
LIMIT 1
END_SQL
        get_latest_revs => <<'END_SQL',
SELECT b.is_deleted, b.blob_name, b.revision FROM revision_log AS r
INNER JOIN blobs AS b
ON  r.blob_id = b.blob_id
WHERE b.user_id     = ?
AND   r.revision_id > ?
ORDER BY r.revision_id DESC
END_SQL
        get_all_revs => <<'END_SQL',
SELECT b.is_deleted, b.blob_name, b.revision FROM revision_log AS r
INNER JOIN blobs AS b
ON r.blob_id = b.blob_id
WHERE b.user_id = ?
ORDER BY r.revision_id DESC
END_SQL
    );

    foreach my $k (keys %statements) {
        $statements{$k} = $dbh->prepare($statements{$k});
    }

    return \%statements;
}

sub _blob_to_disk_name {
    my ( $self, $blob_name ) = @_;

    return encode_base64($blob_name, '');
}

sub _save_blob_to_disk {
    my ( $self, $user, $blob, %options ) = @_;

    my $revision = $options{'revision'} || '';
    my $metadata = $options{'metadata'};
    my $src      = $options{'handle'};

    my $disk_name      = $self->_blob_to_disk_name($blob);
    my $path           = File::Spec->catfile($self->storage_path, $user, $disk_name);
    my ( undef, $dir ) = File::Spec->splitpath($path);
    my $buf            = '';
    my $n;

    make_path $dir;
    my $digest = Digest::SHA->new(1);
    $digest->add($blob);
    $digest->add($revision);
    if(defined $src) {
        foreach my $k (sort keys %$metadata) {
            my $v = $metadata->{$k};
            $digest->add($k);
            $digest->add($v);
        }
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

        unlink($path) || croak "Unable to delete '$path': $!";
    }

    return $digest->hexdigest;
}

sub _get_user_id {
    my ( $self, $user ) = @_;

    my $sth = $self->_statements->{'get_user_id'};

    $sth->execute($user);
    my ( $user_id ) = $sth->fetchrow_array;
    unless(defined $user_id) {
        SaharaSync::X::BadUser->throw({
            username => $user,
        });
    }

    return $user_id;
}

sub create_user { ## no critic (Subroutines::RequireFinalReturn)
    my ( $self, $username, $password ) = @_;

    my $stmts = $self->_statements;

    my $sth = $stmts->{'get_user_id'};
    $sth->execute($username);
    my ( $exists ) = $sth->fetchrow_array;

    if(defined $exists) {
        SaharaSync::X::BadUser->throw({
            username => $username,
        });
    } else {
        $stmts->{'insert_user'}->execute($username, $password);
        return 1;
    }
}

sub remove_user { ## no critic (Subroutines::RequireFinalReturn)
    my ( $self, $username ) = @_;

    my $path = File::Spec->catdir($self->storage_path, $username);

    remove_tree $path;

    my $exists = $self->_statements->{'remove_user'}->execute($username) != 0;
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

    my $sth = $self->_statements->{'get_password'};
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

    my $stmts = $self->_statements;
    my $sth   = $stmts->{'fetch_info_for_blob'};

    $sth->execute($blob, $user);

    my ( $user_exists, $blob_id, $revision ) = $sth->fetchrow_array;

    unless($user_exists) {
        SaharaSync::X::BadUser->throw({
            username => $user,
        });
    }

    if(defined $blob_id) {
        my $disk_name = $self->_blob_to_disk_name($blob);
        my $path      = File::Spec->catfile($self->storage_path, $user, $disk_name);
        my $handle    = IO::File->new($path, 'r');
        unless($handle) {
            croak "Unable to open '$path': $!";
        }
        my %metadata = ( revision => $revision );
        $sth = $stmts->{'metadata_for_blob'};
        $sth->execute($blob_id);
        while(my ( $k, $v ) = $sth->fetchrow_array) {
            $metadata{$k} = $v;
        }
        return ( $handle, \%metadata );
    } else {
        return;
    }
}

sub store_blob {
    my ( $self, $user, $blob, $handle, $metadata ) = @_;

    my $revision = delete $metadata->{'revision'};

    my $user_id = $self->_get_user_id($user);
    my $dbh     = $self->dbh;
    my $stmts   = $self->_statements;
    my $sth     = $stmts->{'revision_info_for_blob'};

    $sth->execute($user_id, $blob);
    my ( $is_deleted, $blob_id, $current_revision ) = $sth->fetchrow_array;
    if(defined $current_revision) {
        if($is_deleted) {
            return if defined $revision;
            $revision = $self->_save_blob_to_disk($user, $blob,
                revision => $current_revision,
                metadata => $metadata,
                handle   => $handle,
            );
        } else {
            return unless defined $revision;
            unless($revision eq $current_revision) {
                return;
            }
            $revision = $self->_save_blob_to_disk($user, $blob,
                revision => $revision,
                metadata => $metadata,
                handle   => $handle,
            );
        }
        $dbh->begin_work;
        $stmts->{'update_revision'}->execute($revision, $blob_id);
    } else {
        return if defined $revision;
        $revision = $self->_save_blob_to_disk($user, $blob, 
            metadata => $metadata,
            handle   => $handle,
        );
        $dbh->begin_work;
        $stmts->{'insert_blob'}->execute($user_id, $blob, $revision);
        $blob_id = $dbh->last_insert_id(undef, 'public', 'blobs', undef);
    }
    $stmts->{'update_revlog'}->execute($blob_id, $revision);
    if(! $current_revision || $is_deleted) {
        $stmts->{'delete_metadata'}->execute($blob_id);
    }
    $sth = $stmts->{'insert_metadata'};
    foreach my $k (keys %$metadata) {
        my $v = $metadata->{$k};
        $sth->execute($blob_id, $k, $v);
    }
    $dbh->commit;

    return $revision;
}

sub delete_blob {
    my ( $self, $user, $blob, $revision ) = @_;

    my $user_id = $self->_get_user_id($user);
    my $dbh     = $self->dbh;
    my $stmts   = $self->_statements;

    my $sth = $stmts->{'revision_info_for_existing_blob'};
    $sth->execute($user_id, $blob);
    my ( $blob_id, $current_revision ) = $sth->fetchrow_array;

    unless(defined $current_revision) {
        SaharaSync::X::NoSuchBlob->throw({
            blob => $blob,
        });
    }
    unless($revision eq $current_revision) {
        return;
    }

    $revision = $self->_save_blob_to_disk($user, $blob,
        revision => $revision,
    );

    $dbh->begin_work;
    $stmts->{'mark_blob_deleted'}->execute($revision, $user_id, $blob);
    $stmts->{'update_revlog'}->execute($blob_id, $revision);
    $dbh->commit;

    return $revision;
}

sub fetch_changed_blobs {
    my ( $self, $user, $last_revision, $metadata ) = @_;

    my $user_id = $self->_get_user_id($user);
    my $stmts   = $self->_statements;
    my $sth;

    $metadata ||= [];

    if(defined $last_revision) {
        $sth = $stmts->{'get_revision_id'};
        $sth->execute($user_id, $last_revision);
        my ( $rev_id ) = $sth->fetchrow_array;

        unless(defined $rev_id) {
            SaharaSync::X::BadRevision->throw({
                revision => $last_revision,
            });
        }

        $sth = $stmts->{'get_latest_revs'};
        $sth->execute($user_id, $rev_id);
    } else {
        $sth = $stmts->{'get_all_revs'};
        $sth->execute($user_id);
    }

    my %blobs;
    my @blob_names;

    while(my ( $is_deleted, $blob, $revision ) = $sth->fetchrow_array) {
        push @blob_names, $blob unless exists $blobs{$blob};
        $blobs{$blob} = {
            name     => $blob,
            revision => $revision,
            $is_deleted ? (is_deleted => 1) : (),
        };
    }

    if(@$metadata) {
        my $in_clause = 'AND m.meta_key IN (' . join(',', map { '?' } @$metadata) . ')';

        my $dbh = $self->dbh;
        $sth    = $dbh->prepare(<<"END_SQL");
SELECT b.blob_name, m.meta_key, m.meta_value FROM blobs AS b
INNER JOIN metadata AS m
ON    m.blob_id = b.blob_id
WHERE b.user_id = ?
$in_clause
END_SQL

        $sth->execute($user_id, @$metadata);
        while(my ( $blob, $key, $value ) = $sth->fetchrow_array) {
            ## horribly inefficent, but working
            unless(exists $blobs{$blob}) {
                next;
            }
            $blobs{$blob}{$key} = $value;
        }
    }

    return map { $blobs{$_} } reverse @blob_names;
}

1;

__END__

# ABSTRACT: Storage plugin that leverages a database and the local filesystem

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head2 $store->create_user($username, $password)

L<SaharaSync::Hostd::Plugin::Store/create_user>

=head2 $store->remove_user($username)

L<SaharaSync::Hostd::Plugin::Store/remove_user>

=head2 $store->load_user_info($username)

L<SaharaSync::Hostd::Plugin::Store/load_user_info>

=head2 $store->fetch_blob($user, $blob)

L<SaharaSync::Hostd::Plugin::Store/fetch_blob>

=head2 $store->store_blob($user, $blob, $handle, $revision)

L<SaharaSync::Hostd::Plugin::Store/store_blob>

=head2 $store->delete_blob($user, $blob, $revision)

L<SaharaSync::Hostd::Plugin::Store/delete_blob>

=head2 $store->fetch_changed_blobs($user, $since_revision)

L<SaharaSync::Hostd::Plugin::Store/fetch_changed_blobs>

=head1 SEE ALSO

SaharaSync::Hostd
SaharaSync::Hostd::Plugin::Store

=cut
