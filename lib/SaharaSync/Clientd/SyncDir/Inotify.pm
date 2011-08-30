package SaharaSync::Clientd::SyncDir::Inotify;

use Moose;

use autodie qw(chmod opendir);
use AnyEvent;
use DBI;
use Digest::SHA;
use Guard qw(guard);
use File::Find;
use File::Spec;
use File::Temp;
use Linux::Inotify2;
use List::MoreUtils qw(any);
use SaharaSync::Clientd::SyncDir::Inotify::Handle;
use Scalar::Util qw(weaken);

use namespace::clean -except => 'meta';

has root => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has change_callbacks => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { [] },
);

has dbh => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_dbh',
);

has _inotify_handle => (
    is      => 'ro',
    default => sub { Linux::Inotify2->new || die $! },
);

has _inotify_watcher => (
    is       => 'ro',
    lazy     => 1,
    builder  => '_build_inotify_watcher',
    init_arg => undef,
);

has _pending_deletes => (
    is       => 'ro',
    default  => sub { [] },
    init_arg => undef,
);

has _pending_updates => (
    is       => 'ro',
    default  => sub { {} },
    init_arg => undef,
);

has _event_queue => (
    is       => 'ro',
    default  => sub { [] },
    init_arg => undef,
);

sub BUILD {
    my ( $self ) = @_;

    mkdir($self->_overlay);
    $self->_inotify_watcher; ## kick that lazy attribute!
}

sub _overlay {
    my ( $self ) = @_;

    return File::Spec->catdir($self->root, '.saharasync');
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

sub _update_queue {
    my ( $self, $event ) = @_;

    my $path  = $event->{'path'};
    my $queue = $self->_event_queue;
    @$queue   = grep { $_->{'path'} ne $path } @$queue;
    push @$queue, $event;
}

sub _handle_inotify_overflow {
    my ( $self, $e ) = @_;

    ## OH SHIT
}

sub _process_inotify_event {
    my ( $self, $e ) = @_;

    my $path = $e->fullname;
    my $mask = IN_CREATE | IN_CLOSE_WRITE | IN_MOVE | IN_DELETE;

    if($e->IN_CREATE) {
        if($e->IN_ISDIR) {
            my $watcher = $self->_inotify_handle->watch($path, $mask, sub {
                $self->_process_inotify_event(@_);
            });

            my $dh;
            opendir $dh, $path;
            while(my $file = readdir $dh) {
                next if $file eq '.' ||
                        $file eq '..';

                my $fullpath = File::Spec->catfile($path, $file);

                my $event;
                if(-d $fullpath) {
                    $event = $self->create_fake_event(
                        name => $file,
                        mask => IN_CREATE | IN_ISDIR,
                        w    => $watcher,
                    );
                } else {
                    $event = $self->create_fake_event(
                        name => $file,
                        mask => IN_CLOSE_WRITE,
                        w    => $watcher,
                    );
                }
                $self->_process_inotify_event($event);
            }
            closedir $dh;
        }
        return;
    }

    my $event = {
        path => $path,
    };

    if($e->IN_Q_OVERFLOW) {
        $self->_handle_inotify_overflow($e);
    }
    if($e->IN_MOVE) {
        my $cookie = $e->cookie;

        if($e->IN_MOVED_FROM) {
            push @{$self->_pending_deletes}, [ $cookie, $event ];
            return; # further processing comes later
        } else { # IN_MOVED_TO
            if(delete $self->_pending_updates->{$cookie}) {
                return; # we ignore events we generate ourselves
            } elsif(any { $_->[0] eq $cookie } @{$self->_pending_deletes}) {
                push @{$self->_pending_deletes}, [ $cookie, $event ];
                return;
            }
            # handle like a close_write
        }
    }
    $self->_process_event($event);
}

sub _process_event {
    my ( $self, $event ) = @_;

    my $path = $event->{'path'};
    my $root = $self->root;
    my $file = File::Spec->abs2rel($path, $root);

    $self->_update_file_stats($path, $file);
    $self->_update_queue($event);

    my $callbacks = $self->change_callbacks;

    foreach my $cb (@$callbacks) {
        $cb->($event);
    }
}

sub _process_overlay_event {
    my ( $self, $e ) = @_;

    my $cookie = $e->cookie;

    if($e->IN_MOVED_FROM) {
        $self->_pending_updates->{$cookie} = 1;
    } else { # IN_MOVED_TO
        if(delete $self->_pending_updates->{$cookie}) {
            return;
        } else {
            @{$self->_pending_deletes} = grep {
                $_->[0] ne $cookie
            } @{$self->_pending_deletes};
        }
    }
}

sub _flush_pending_events {
    my ( $self ) = @_;
}

sub _build_inotify_watcher {
    my ( $self ) = @_;

    my $mask = IN_CREATE | IN_CLOSE_WRITE | IN_MOVE | IN_DELETE;
    my $n    = $self->_inotify_handle;

    weaken($self);
    weaken($n);

    my $wrapper = sub {
        $self->_process_inotify_event(@_);
    };

    my $root = $self->root;
    my $watcher = $n->watch($root, $mask, $wrapper);

    my $overlay_watcher = $n->watch($self->_overlay, IN_MOVE, sub {
        $self->_process_overlay_event(@_);
    });

    my $dir;
    opendir $dir, $root or die $!;
    while(my $file = readdir $dir) {
        next if $file eq '.'  ||
                $file eq '..' ||
                $file eq '.saharasync';

        my $path = File::Spec->catdir($root, $file);
        if(-d $path) {
            ## no_chdir!
            find(sub {
                return unless -d;

                $n->watch($_, $mask, $wrapper);
            }, $path);
        } else {
            if($self->_file_has_changed($file, $path)) {
                ## we'll have the checksum calculated here; we should
                ## make use of it
                $self->_process_event({ path => $path });
            }
        }
    }
    close $dir;

    return AnyEvent->io(
        fh   => $n->fileno,
        poll => 'r',
        cb   => sub {
            $n->poll;
            $self->_flush_pending_events;
        },
    );
}

sub _file_has_changed {
    my ( $self, $file, $fullpath ) = @_;

    my $dbh = $self->dbh;
    my $sth = $dbh->prepare('SELECT checksum FROM file_stats WHERE path = ?');

    $sth->execute($file);

    if(my ( $checksum ) = $sth->fetchrow_array) {
        ## this comparison could be far more efficient
        my $digest = Digest::SHA->new(1);
        $digest->addfile($fullpath);

        return $checksum ne $digest->hexdigest;
    }

    return 1;
}

sub _update_file_stats {
    my ( $self, $fullpath, $file ) = @_;

    my $dbh = $self->dbh;

    if(-f $fullpath) {
        my $digest = Digest::SHA->new(1);
        $digest->addfile($fullpath);

        $dbh->do('INSERT OR REPLACE INTO file_stats (path, checksum) VALUES (?, ?)', undef,
            $file, $digest->hexdigest);
    } else {
        $dbh->do('DELETE FROM file_stats WHERE path = ?', undef, $file);
    }
}

sub create_fake_event {
    my ( $self, %attrs ) = @_;

    $attrs{'cookie'} = 0;

    return bless \%attrs, 'Linux::Inotify2::Event';
}

sub _debug_event {
    my ( $self, $event ) = @_;

    my @masks;
    my $mask = $event->mask;

    foreach my $name (@Linux::Inotify2::EXPORT) {
        no strict 'refs';

        my $m = &{"Linux::Inotify2::$name"};

        if($mask & $m) {
            push @masks, $name;
        }
    }

    use Test::More;

    diag("  fullpath: " . $event->fullname);
    diag("  cookie:   " . $event->cookie);
    diag("  mask:     " . join(', ', @masks));
}

sub on_change {
    my ( $self, $callback ) = @_;

    return unless defined(wantarray);

    $callback->($_) foreach @{ $self->_event_queue };

    weaken $self;
    weaken $callback;

    push @{ $self->change_callbacks }, $callback;

    return guard {
        return unless $self; # $self is a weak reference, so check first

        @{ $self->change_callbacks } = grep {
            $_ != $callback
        } @{ $self->change_callbacks };
    };
}

sub open_write_handle {
    my ( $self, $blob_name ) = @_;

    my $current_path = File::Spec->catfile($self->root, $blob_name);
    my $old_mode     = (stat $current_path)[2];
    if(defined $old_mode) {
        my $mode = $old_mode & 07555;

        ## this won't help if a file handle is opened for writing at the time
        chmod $mode, $current_path;
    }
    ## what if file doesn't exist?
    ## chmod parent dir too?
    ## do some more checks?

    my $file = File::Temp->new(DIR => $self->_overlay, UNLINK => 0);
    return SaharaSync::Clientd::SyncDir::Inotify::Handle->new($self, $file, $old_mode,
        $current_path);
}

sub unlink {
    my ( $self, $blob_name ) = @_;

    my $tempfile = File::Temp->new(DIR => $self->_overlay, UNLINK => 0);
    close $tempfile;
    my $path = File::Spec->catfile($self->root, $blob_name);
    rename $path, $tempfile->filename or die $!;
    unlink $tempfile->filename;
    $self->_update_file_stats($path, $blob_name);
}

sub rename {
    my ( $self, $from, $to ) = @_;

    my $tempfile = File::Temp->new(DIR => $self->_overlay, UNLINK => 0);
    close $tempfile;
    my $from_path = File::Spec->catfile($self->root, $from);
    my $to_path   = File::Spec->catfile($self->root, $to);

    rename $from_path, $tempfile->filename or die $!;
    rename $tempfile->filename, $to_path   or die $!;

    $self->_update_file_stats($from_path, $from);
    $self->_update_file_stats($to_path, $to);
}

__PACKAGE__->meta->make_immutable;

1;
