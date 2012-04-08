package SaharaSync::Clientd::BlobStore::Inotify;

use Moose;

with 'SaharaSync::Clientd::BlobStore::Local';

use autodie qw(chmod opendir);
use AnyEvent;
use Carp qw(croak confess);
use DBI;
use Digest::SHA;
use Guard qw(guard);
use File::Find;
use File::Spec;
use File::Temp;
use Linux::Inotify2;
use List::MoreUtils qw(any);
use SaharaSync::Clientd::Blob;
use SaharaSync::Clientd::BlobStore::Inotify::Handle;
use Scalar::Util qw(weaken);

use namespace::clean -except => 'meta';

has change_callbacks => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { [] },
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

has log => (
    is        => 'ro',
    predicate => 'has_log',
);

sub BUILD {
    my ( $self ) = @_;

    $self->_inotify_watcher; ## kick that lazy attribute!
}

sub overlay {
    my ( $self ) = @_;

    return File::Spec->catdir($self->root, '.saharasync');
}

sub _update_queue {
    my ( $self, $event ) = @_;

    my $path  = $event->{'blob'}->path;
    my $queue = $self->_event_queue;
    @$queue   = grep { $_->{'blob'}->path ne $path } @$queue;
    push @$queue, $event;
}

sub _handle_inotify_overflow {
    my ( $self, $e ) = @_;

    ## OH SHIT
}

sub _process_inotify_event {
    my ( $self, $e ) = @_;

    if($self->has_log) {
        $self->log->debug($self->_debug_event($e));
    }

    my $path = $e->fullname;
    my $mask = IN_CREATE | IN_CLOSE_WRITE | IN_MOVE | IN_DELETE;

    if($e->IN_CREATE) {
        if($e->IN_ISDIR) {
            weaken($self);
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
        blob => $self->blob(path => $path),
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

    my $blob = $event->{'blob'};

    $self->_update_queue($event);

    my $called = 0;
    my $continuation = sub {
        unless($called) {
            $called = 1;
            $self->update_file_stats($blob);
        }
    };

    my $callbacks = $self->change_callbacks;

    foreach my $cb (@$callbacks) {
        $cb->($self, $event, $continuation);
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

    my $pending = $self->_pending_deletes;
    foreach my $event (@$pending) {
        $self->_process_event($event->[1]);
    }
    @$pending = ();
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

    my $overlay_watcher = $n->watch($self->overlay, IN_MOVE, sub {
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
                $self->_process_event({ blob => $self->blob(path => $path) });
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
        my $glob = $Linux::Inotify2::{$name};
        my $m    = *{$glob}{'CODE'}->();

        # check if $m is a power of two first
        if(($m & $m - 1) == 0 && $mask & $m) {
            push @masks, $name;
        }
    }

    return sprintf('fullpath = %s, cookie = %s, mask = %s',
        $event->fullname,
        $event->cookie,
        join(', ', @masks));
}

# XXX I'm sure much of this can be abstracted away in a base class
sub on_change {
    my ( $self, $callback ) = @_;

    return unless defined(wantarray);

    ## XXX $continuation?
    $callback->($self, $_, sub {}) foreach @{ $self->_event_queue };

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
    my ( $self, $blob ) = @_;

    my $current_path = $blob->path;
    my $old_mode     = (stat $current_path)[2];
    if(defined $old_mode) {
        my $mode = $old_mode & 07555;

        ## this won't help if a file handle is opened for writing at the time
        chmod $mode, $current_path;
    }
    ## what if file doesn't exist?
    ## chmod parent dir too?
    ## do some more checks?

    my $file = File::Temp->new(DIR => $self->overlay);
    return SaharaSync::Clientd::BlobStore::Inotify::Handle->new($self, $file, $old_mode,
        $blob);
}

sub unlink {
    my ( $self, $blob, $cont ) = @_;

    croak "Continuation needed" unless $cont;
    my $ok = 1;
    
    my $path     = $blob->path;
    my $tempfile = File::Temp->new(DIR => $self->overlay, UNLINK => 0);
    close $tempfile;
    unless(CORE::rename $path, $tempfile->filename) {
        unless(-e $path) {
            if($self->is_known_blob($blob)) {
                $cont->(undef, 'conflict');
                return;
            }
            $cont->(undef, $!);
            return;
        } else {
            die $!;
        }
    }
    if($self->verify_blob($blob, $tempfile->filename)) {
        # XXX check errors?
        unlink $tempfile->filename;
    } else {
        # XXX push errors to $cont?
        rename $tempfile->filename, $path or die $!;
        $cont->(undef, 'conflict');
        $ok = 0;
        ## return here?
    }
    # XXX do we want to do this if not $ok?
    $self->update_file_stats($blob);

    $cont->($ok) if $ok;
}

sub rename {
    my ( $self, $from, $to, $cont ) = @_;

    croak "Continuation needed" unless $cont;

    my $tempfile = File::Temp->new(DIR => $self->overlay, UNLINK => 0);
    close $tempfile;

    unless(CORE::rename $from->path, $tempfile->filename) {
        unless(-e $from->path) {
            if($self->is_known_blob($from)) {
                $cont->(undef, 'conflict');
                return;
            }
        }
        $cont->(undef, $!);
        return;
    }

    unless($self->verify_blob($from, $tempfile->filename)) {
        link $tempfile->filename, $from->path; # XXX check error
        $cont->(undef, 'conflict');
        return;
    }
    unless(link $tempfile->filename, $to->path) {
        link $tempfile->filename, $from->path; # XXX check error
        $cont->(undef, $!);
        return;
    }

    # XXX do we want to do this if not $ok?
    $self->update_file_stats($from);
    $self->update_file_stats($to);

    $cont->(1);
}

__PACKAGE__->meta->make_immutable;

1;
