package SaharaSync::Clientd::SyncDir::FSEvents;

use Moose;

use autodie qw(opendir);

use Cwd qw(realpath);
use DBI;
use File::Find;
use File::Spec;
use Mac::FSEvents ();
use Scalar::Util qw(weaken);

use SaharaSync::Clientd::Blob;

sub is_same_file {
    my ( $lhs, $rhs ) = @_;

    my ( $dev_lhs, $inode_lhs ) = (stat $lhs)[0, 1];
    my ( $dev_rhs, $inode_rhs ) = (stat $rhs)[0, 1];

    return $dev_lhs == $dev_rhs && $inode_lhs == $inode_rhs;
}

use namespace::clean;

has root => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has _fs_events => (
    is         => 'ro',
    lazy_build => 1,
);

has _fs_watcher => (
    is         => 'ro',
    lazy_build => 1,
);

has dbh => (
    is         => 'ro',
    lazy_build => 1,
);

has change_callbacks => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
);

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

sub _update_file_stats {
    my ( $self, $path ) = @_;

    my $dbh = $self->dbh;

    my ( $mtime ) = (stat $path)[9];

    my $insert_or_update_sth = $dbh->prepare(<<'END_SQL');
INSERT OR REPLACE INTO file_stats (path, mtime) VALUES (?, ?)
END_SQL

    $insert_or_update_sth->execute($path, $mtime);
}

sub _inform_listeners {
    my ( $self, $path ) = @_;

    my $callbacks = $self->change_callbacks;

    my $event = {
        blob => $self->blob(path => $path),
    };

    my $called = 0;
    my $continuation = sub {
        unless($called) {
            $called = 1;
            # XXX this internal API is inconsistent with Inotify.pm.  This
            #     isn't *that* big of a deal, but it might be nice for them
            #     to be similar if we intend to merge the two in the future
            $self->_update_file_stats($path);
        }
    };

    foreach my $callback (@$callbacks) {
        $callback->($self, $event, $continuation);
    }
}

sub _check_file {
    my ( $self, $path ) = @_;

    my $current_mtime = (stat $path)[9];

    my $dbh = $self->dbh;

    my $lookup_sth = $dbh->prepare('SELECT mtime FROM file_stats WHERE path = ?');

    $lookup_sth->execute($path);

    my ( $previous_mtime ) = $lookup_sth->fetchrow_array;

    $previous_mtime //= 0;

    if($previous_mtime < $current_mtime) {
        $self->_inform_listeners($path);
    }
}

sub _overlay {
    my ( $self ) = @_;

    return File::Spec->catdir($self->root, '.saharasync');
}

sub _handle_fs_event {
    my ( $self, $event ) = @_;

    my $path    = $event->path;
    my $dropped = $event->user_dropped || $event->kernel_dropped;

    if(is_same_file($path, $self->_overlay)) {
        return;
    }

    if($dropped) {
        # XXX uh-oh!
    }

    if($event->must_scan_subdirs) {
        # XXX don't recurse into $overlay
        find({
            no_chdir => 1,
            wanted   => sub {
                return unless -f $File::Find::name;

                $self->_check_file($File::Find::name);
            },
        }, $path);
    } else {
        my $dh;
        opendir $dh, $path;

        while(my $filename = readdir $dh) {
            next if $filename eq '.' || $filename eq '..';
            my $fullpath = File::Spec->catfile($path, $filename);

            next unless -f $fullpath;

            $self->_check_file($fullpath);
        }
    }
}

sub _init_db {
    my ( $self, $dbh ) = @_;

    $dbh->do(<<SQL);
CREATE TABLE IF NOT EXISTS file_stats (
    path     TEXT    NOT NULL UNIQUE,
    mtime    INTEGER NOT NULL
)
SQL
}

sub _build_dbh {
    my ( $self ) = @_;

    my $path = File::Spec->catfile($self->_overlay, 'events.db');
    my $dbh  = DBI->connect('dbi:SQLite:dbname=' . $path, '', '', {
        PrintError => 0,
        RaiseError => 1,
    });

    $self->_init_db($dbh);

    return $dbh;
}

sub _build__fs_events {
    my ( $self ) = @_;

    # XXX since parameter
    return Mac::FSEvents->new({
        path    => $self->root,
        latency => 0.5, # XXX for now
    });
}

sub _build__fs_watcher {
    my ( $self ) = @_;

    my $fs_events = $self->_fs_events;
    my $fh        = $fs_events->watch;

    weaken($self);

    return AnyEvent->io(
        fh   => $fh,
        poll => 'r',
        cb   => sub {
            my @events = $fs_events->read_events;

            foreach my $event (@events) {
                $self->_handle_fs_event($event);
            }
        },
    );
}

sub BUILD {
    my ( $self ) = @_;

    mkdir($self->_overlay);
    $self->_fs_watcher; # make sure it gets built
}

sub on_change {
    my ( $self, $callback ) = @_;

    push @{ $self->change_callbacks }, $callback;
}

around root => sub {
    my ( $orig, $self ) = @_;

    my $root = $self->$orig();

    return realpath($root);
};

1;

__END__

# ABSTRACT: Sync directory implementation for FSEvents

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
