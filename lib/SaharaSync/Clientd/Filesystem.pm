package SaharaSync::Clientd::Filesystem;

use Moose;

use autodie qw(chmod opendir);
use AnyEvent;
use File::Find;
use File::Spec;
use File::Temp;
use Linux::Inotify2;
use SaharaSync::Clientd::Filesystem::Handle;

use namespace::clean -except => 'meta';

has root => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
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

    my $mask = IN_CREATE | IN_CLOSE_WRITE | IN_MOVE | IN_DELETE;
    my $root = $self->root;
    my $n    = Linux::Inotify2->new || die $!;

    my $overlay_watcher;
    my %pending_moves;

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

        if($e->IN_Q_OVERFLOW) {
            ## OH SHIT
        }
        if($e->IN_MOVE) {
            my $cookie = $e->cookie;

            if($e->IN_MOVED_FROM) {
                my $w = $e->w;
                if($w == $overlay_watcher) {
                    $pending_moves{$cookie} = 1;
                    return; # further processing comes later
                }
            } else { # IN_MOVED_TO
                if(delete $pending_moves{$cookie}) {
                    return; # we ignore events we generate ourselves
                } else {
                    ## handle like a close_write
                }
            }
        }
        $callback->({
            path => $path,
        });
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
            $overlay_watcher = $n->watch($file, IN_MOVED_FROM, $wrapper);
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

    return AnyEvent->io(
        fh   => $n->fileno,
        poll => 'r',
        cb   => sub { $n->poll },
    );
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
    return SaharaSync::Clientd::Filesystem::Handle->new($file, $old_mode,
        $current_path);
}

sub create_filesystem {
    my ( $class, %args ) = @_;

    return $class->new(%args);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
