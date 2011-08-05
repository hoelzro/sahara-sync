## no critic (RequireUseStrict)
package SaharaSync::Clientd;

## use critic (RequireUseStrict)

use Moose;
use autodie qw(mkdir);
use AnyEvent::Filesys::Notify;
use AnyEvent::WebService::Sahara;
use Carp qw(croak);
use File::Path qw(make_path);
use File::Slurp qw(read_file);
use File::Spec;
use IO::File;
use Log::Dispatch;
use Path::Class;
use URI;

use SaharaSync::Clientd::SyncDir;

use namespace::clean -except => 'meta';

has [qw/username password/] => (
    is  => 'ro',
    isa => 'Str',
);

has upstream => (
    is       => 'ro',
    isa      => 'URI',
    required => 1,
);

has sync_dir => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    required => 1,
);

has sd => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_sd',
);

has _sync_dir_guard => (
    is => 'rw',
);

has ws_client => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_ws_client',
);

has log => (
    is => 'ro',
);

## make sure we handle SIGINT, SIGTERM

my $client;

sub BUILDARGS {
    my $class = shift;
    my %args;

    if(@_ == 1) {
        my $arg = $_[0];

        ## superclass/role for this
        if(ref($arg) eq 'HASH' || ref($arg) eq 'SaharaSync::Clientd::Config') {
            %args = %$arg;
        } else {
            croak "Invalid config object to " . __PACKAGE__ . ": $arg";
        }
    } else {
        %args = @_;
    }

    my $log = $args{'log'};
    my @outputs;
    foreach my $config (@$log) {
        my $type = delete $config->{'type'};
        push @outputs, [ $type, %$config ];
    }

    $args{'log'} = Log::Dispatch->new(outputs => \@outputs);

    return \%args;
}

sub _build_sd {
    my ( $self ) = @_;

    return SaharaSync::Clientd::SyncDir->create_syncdir(
        root => $self->sync_dir . '',
    );
}

sub _build_ws_client {
    my ( $self ) = @_;

    return AnyEvent::WebService::Sahara->new(
        url      => $self->upstream,
        user     => $self->username,
        password => $self->password,
    );
}

sub _get_last_sync {
    my ( $self ) = @_;

    return;
}

sub _get_revision_for_blob {
    my ( $self, $blob ) = @_;

    ## if a blob was deleted, don't return anything!
    return;
}

sub _put_revision_for_blob {
    my ( $self, $blob, $revision, $is_deleted ) = @_;
}

sub handle_fs_change {
    my ( $self, @events ) = @_;

    foreach my $event (@events) {
        ## if $event is just a metadata (ex. permissions) change, do something
        ## about it

        my $path = $event->{'path'};
        $self->log->info("$path changed on filesystem!");

        my $blob = File::Spec->abs2rel($path, $self->sync_dir);
        ## make sure to send blobs names in Unix style file format

        my $revision = $self->_get_revision_for_blob($blob);

        if(-f $path) {
            $self->log->info(sprintf("Sending PUT %s/blobs/%s",
                $self->upstream, $blob));

            my %meta;
            ## attach metadata (MIME Type, File Size, Contents Hash)

            if(defined $revision) {
                $meta{'revision'} = $revision;
            }

            $self->ws_client->put_blob($blob, IO::File->new($path, 'r'),
                \%meta, sub {
                    my ( $revision, $error ) = @_;

                    if(defined $revision) {
                        $self->log->info("Successfully updated $blob; new revision is $revision");
                        $self->_put_revision_for_blob($blob, $revision, 0);
                    } else {
                        $self->log->warning("Updating $blob failed: $error");
                    }
            });
        } else {
            $self->log->info(sprintf("Sending DELETE %s/blobs/%s",
                $self->upstream, $blob));

            $self->ws_client->delete_blob($blob, $revision, sub {
                my ( $revision, $error ) = @_;

                if(defined $revision) {
                    $self->log->info("Successfully deleted $blob; new revision is $revision");
                    $self->_put_revision_for_blob($blob, $revision, 1);
                } else {
                    $self->log->warning("Deleting $blob failed: $error");
               }
            });
        }
    }
}

sub handle_upstream_change {
    my ( $self, $change, $error ) = @_;

    unless(defined $change) {
        $self->log->warning("An error occurred while fetching changes: $error");
        return;
    }

    my $blob = $change->{'name'};

    $self->ws_client->get_blob($blob, sub {
        my ( $h, $metadata ) = @_;

        ## handle error

        my $w = $self->sd->open_write_handle($blob);

        $h->on_read(sub {
            my $buffer = $h->rbuf;
            $h->rbuf = '';

            $w->write($buffer);
        });

        $h->on_error(sub {
            ## do something
        });

        $h->on_eof(sub {
            $w->close;
            undef $h;
        });
    });

    ## if the change is one that we made (ex. a local file changed, and we
    ## sent the update), ignore it

    ## lock the file
    ## make sure it hasn't changed on the local machine since our latest revision
    ## if it has, mark as conflicted and update
    ## if not, just update its contents
    ## unlock the file

    ## update last sync (both here, and in persistent storage)
    ## handle case conflicts
    ## handle bad characters for the filesystem you're on
}

sub run {
    my ( $self ) = @_;

    mkdir $self->sync_dir unless -d $self->sync_dir;

    my $last_revision = $self->_get_last_sync;

    my $guard = $self->sd->on_change(sub {
        return $self->handle_fs_change(@_);
    });

    $self->_sync_dir_guard($guard);

    $self->ws_client->changes($last_revision, [], sub {
        return $self->handle_upstream_change(@_);
    });

    ## scan sync dir, send blobs that have changed since we last ran

    my $cond = AnyEvent->condvar;
    $cond->recv;
}

## if server connection drops, we need to queue up fs events or something
## what if someone adds/changes/deletes files when the client isn't running?
## max updates per file per second
## checksum chunking (sha256 first 4K bytes, then 8K, 16K, 32K, etc)
## what if I submit 2 more PUTs while I'm still waiting for the result of another PUT?

__PACKAGE__->meta->make_immutable;

1;

__END__

# ABSTRACT: Client daemon for Sahara Sync

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=head1 SEE ALSO

=cut
