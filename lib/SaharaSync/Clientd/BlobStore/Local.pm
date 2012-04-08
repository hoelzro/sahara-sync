package SaharaSync::Clientd::BlobStore::Local;

use Moose::Role;
use Digest::SHA;
use DBI;
use File::Spec;

with 'SaharaSync::Clientd::BlobStore';

requires 'overlay';

has root => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has dbh => (
    is         => 'ro',
    lazy_build => 1,
);

sub _build_dbh {
    my ( $self ) = @_;

    my $path = File::Spec->catfile($self->overlay, 'events.db');
    my $dbh  = DBI->connect('dbi:SQLite:dbname=' . $path, undef, undef, {
        PrintError => 0,
        RaiseError => 1,
    });

    $self->_init_db($dbh);

    return $dbh;
}

sub _init_db {
    my ( $self, $dbh ) = @_;

    $dbh->do(<<SQL);
CREATE TABLE IF NOT EXISTS file_stats (
    path     TEXT NOT NULL UNIQUE,
    checksum TEXT NOT NULL
)
SQL
}

sub update_file_stats {
    my ( $self, $blob ) = @_;

    my $dbh = $self->dbh;

    if(-f $blob->path) {
        my $digest = Digest::SHA->new(1);
        $digest->addfile($blob->path);

        $dbh->do('INSERT OR REPLACE INTO file_stats (path, checksum) VALUES (?, ?)', undef,
            $blob->name, $digest->hexdigest);
    } else {
        $dbh->do('DELETE FROM file_stats WHERE path = ?', undef, $blob->name);
    }
}

sub is_known_blob {
    my ( $self, $blob ) = @_;

    my ( $count ) = $self->dbh->selectrow_array(<<'END_SQL', undef, $blob->name);
SELECT COUNT(1) FROM file_stats WHERE path = ?
END_SQL

    return $count > 0;
}

sub verify_blob {
    my ( $self, $blob, $old_path ) = @_;

    my $dbh = $self->dbh;

    my $digest = Digest::SHA->new(1);
    $digest->addfile($old_path);
    $digest = $digest->hexdigest;

    # XXX path is probably not the best name for the field
    my ( $count ) = $dbh->selectrow_array(<<'END_SQL', undef, $blob->name, $digest);
SELECT COUNT(1) FROM file_stats WHERE path = ? AND checksum = ?
END_SQL

    return $count > 0;
}

# XXX will I even need this?
sub blob {
    my ( $self, $type, $name ) = @_;

    if($type eq 'path') {
        $name = File::Spec->abs2rel($name, $self->root);
    } elsif($type ne 'name') {
        confess "Invalid blob type '$type'";
    }

    return SaharaSync::Clientd::Blob->new(
        name => $name,
        root => $self->root,
    );
}

before BUILD => sub {
    my ( $self ) = @_;

    mkdir($self->overlay);
};

1;

__END__

# ABSTRACT:

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
