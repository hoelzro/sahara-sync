package SaharaSync::Clientd::SyncDir::Inotify;

use Moose;

use autodie qw(chmod opendir);
use AnyEvent;
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

has change_guards => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { [] },
);

sub BUILD {
    my ( $self ) = @_;

    mkdir($self->_overlay);
}

sub _overlay {
    my ( $self ) = @_;

    return File::Spec->catdir($self->root, '.saharasync');
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

    weaken $self;

    my $mask = IN_CREATE | IN_CLOSE_WRITE | IN_MOVE | IN_DELETE;
    my $root = $self->root;
    my $n    = Linux::Inotify2->new || die $!;

    my $overlay_watcher;
    my %pending_updates;
    my @pending_deletes;

    my $wrapper;
    $wrapper = sub {
        my ( $e ) = @_;

        my $path = $e->fullname;

        if($e->IN_CREATE) {
            if($e->IN_ISDIR) {
                my $watcher = $n->watch($path, $mask, $wrapper);

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
                    $wrapper->($event);
                }
                closedir $dh;

                # if a file under $path existed before we created the watcher,
                # we should not get an IN_CREATE event for it

                # emit events for all files, and ignore the next close event for
                # files that emit a create event?
            }

            return;
        }

        my $event = {
            path => $path,
        };

        if($e->IN_Q_OVERFLOW) {
            ## OH SHIT
        }
        if($e->IN_MOVE) {
            my $cookie = $e->cookie;

            if($e->IN_MOVED_FROM) {
                my $w = $e->w;
                if($w == $overlay_watcher) {
                    $pending_updates{$cookie} = 1;
                } else {
                    push @pending_deletes, [ $cookie, $event ];
                }
                return; # further processing comes later
            } else { # IN_MOVED_TO
                if(delete $pending_updates{$cookie}) {
                    return; # we ignore events we generate ourselves
                } else {
                    my $w = $e->w;

                    if($w == $overlay_watcher) {
                        @pending_deletes = grep {
                            $_->[0] ne $cookie
                        } @pending_deletes;
                        return;
                    } elsif(any { $_->[0] eq $cookie } @pending_deletes) {
                        push @pending_deletes, [ $cookie, $event ];
                        return;
                    }
                    ## handle like a close_write
                }
            }
        }
        $callback->($event);
    };

    $n->watch($root, $mask, $wrapper);
    my $dir;
    opendir $dir, $root or die $!;
    while(my $file = readdir $dir) {
        next if $file eq '.' ||
                $file eq '..';

        if($file eq '.saharasync') {
            $file = File::Spec->catdir($root, $file);
            ## special wrapper for .saharasync?
            $overlay_watcher = $n->watch($file, IN_MOVE, $wrapper);
        } else {
            $file = File::Spec->catdir($root, $file);
            next unless -d $file;

            ## no_chdir!
            find(sub {
                return unless -d;

                $n->watch($_, $mask, $wrapper);
            }, $file);
        }
    }

    closedir $dir;

    ## verify that $overlay_watcher is defined?

    my $io = AnyEvent->io(
        fh   => $n->fileno,
        poll => 'r',
        cb   => sub {
            $n->poll;
            ## the naming of this var sucks
            foreach my $info (@pending_deletes) {
                $callback->($info->[1]);
            }
            @pending_deletes = ();
        },
    );

    push @{ $self->change_guards }, $io;
    weaken $io;

    return guard {
        return unless $self; # $self is a weak reference, so check first

        @{ $self->change_guards } = grep {
            $_ != $io
        } @{ $self->change_guards };
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
    return SaharaSync::Clientd::SyncDir::Inotify::Handle->new($file, $old_mode,
        $current_path);
}

sub unlink {
    my ( $self, $blob_name ) = @_;

    my $tempfile = File::Temp->new(DIR => $self->_overlay, UNLINK => 0);
    close $tempfile;
    my $path = File::Spec->catfile($self->root, $blob_name);
    rename $path, $tempfile->filename or die $!;
    unlink $tempfile->filename;
}

__PACKAGE__->meta->make_immutable;

1;
