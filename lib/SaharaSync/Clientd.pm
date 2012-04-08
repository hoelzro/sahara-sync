## no critic (RequireUseStrict)
package SaharaSync::Clientd;

## use critic (RequireUseStrict)

use Moose;
use autodie qw(mkdir);
use AnyEvent::WebService::Sahara;
use Carp qw(croak longmess);
use DBI;
use Errno qw(EEXIST);
use File::Path qw(make_path);
use File::Slurp qw(read_file);
use File::Spec;
use IO::File;
use Log::Dispatch;
use Path::Class;
use URI;

use SaharaSync::Clientd::BlobStore;
use SaharaSync::Util;

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

has store => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_store',
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

has poll_interval => (
    is       => 'ro',
    required => 1,
);

has dbh => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_dbh',
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

    $args{'log'} = SaharaSync::Util->load_logger($args{'log'});

    return \%args;
}

sub _build_store {
    my ( $self ) = @_;

    return SaharaSync::Clientd::BlobStore->create(
        root => $self->sync_dir . '',
    );
}

sub _build_ws_client {
    my ( $self ) = @_;

    return AnyEvent::WebService::Sahara->new(
        url           => $self->upstream,
        user          => $self->username,
        password      => $self->password,
        poll_interval => $self->poll_interval,
    );
}

sub _build_dbh {
    my ( $self ) = @_;

    my $db_path = File::Spec->catfile($self->sync_dir, '.saharasync', 'blobs.db');
    my $dbh     = DBI->connect('dbi:SQLite:dbname=' . $db_path, '', '', {
        PrintError => 0,
        RaiseError => 1,
    });

    $self->_init_db($dbh);
    return $dbh;
}

sub _init_db {
    my ( $self, $dbh ) = @_;

    $dbh->do(<<SQL);
CREATE TABLE IF NOT EXISTS local_revisions (
    filename   TEXT    NOT NULL UNIQUE,
    revision   TEXT    NOT NULL,
    is_deleted INTEGER NOT NULL
)
SQL

    $dbh->do(<<SQL);
CREATE TABLE IF NOT EXISTS reconnect_queue (
    id          INTEGER NOT NULL PRIMARY KEY,
    method_name TEXT    NOT NULL,
    blob_name   TEXT    NOT NULL
)
SQL
}

sub _get_last_sync {
    my ( $self ) = @_;

    return;
}

sub _get_revision_for_blob {
    my ( $self, $blob ) = @_;

    my $sth = $self->dbh->prepare('SELECT revision from local_revisions WHERE filename = ? AND is_deleted = 0 LIMIT 1');
    $sth->execute($blob->name);

    if(my ( $revision ) = $sth->fetchrow_array) {
        return $revision;
    }
    return;
}

sub _put_revision_for_blob {
    my ( $self, $blob, $revision, $is_deleted ) = @_;

    $self->dbh->do('INSERT OR REPLACE INTO local_revisions VALUES (?, ?, ?)',
        undef, $blob->name, $revision, $is_deleted);
}

sub _wait_for_reconnect {
    my ( $self, $method, $blob_name ) = @_;

    $self->log->info("enqueueing operation '$method' for blob '$blob_name'");

    $self->dbh->do('INSERT INTO reconnect_queue (method_name, blob_name) VALUES (?, ?)',
        undef, $method, $blob_name);
}

sub _flush_reconnect_queue {
    my ( $self ) = @_;

    my $sth        = $self->dbh->prepare('SELECT id, method_name, blob_name FROM reconnect_queue');
    my $delete_sth = $self->dbh->prepare('DELETE FROM reconnect_queue WHERE id = ?');
    $sth->execute;

    # XXX potential problems with this implementation:
    # 
    # - if each operation submits an HTTP request, they all get fired in a shotgun blast
    # - there is a a potential problem if we do half of the operations and then die (our next run will pick up operations we've executed)
    # - redundant operations can exist in the DB (like put_blob('foo.txt'), put_blob('foo.txt'))
    #   - what if I do put_blob('foo.txt') + delete_blob('foo.txt')? or the reverse?
    # - if any of the operations throw an exception, we may re-execute operations
    # - think of what issues can occur if there are multiple entries in the queue

    while(my ( $id, $method, $blob_name ) = $sth->fetchrow_array) {
        $self->log->info("running queued operation '$method' on blob '$blob_name'");
        $self->$method($blob_name, sub {
            $delete_sth->execute($id);
        });
    }
}

sub _fetch_and_write_blob {
    my ( $self, $blob_name, $on_complete ) = @_;

    my $ws    = $self->ws_client;
    my $store = $self->store;
    my $blob  = $store->blob(name => $blob_name);

    $ws->get_blob($blob->name, sub {
        my ( $ws, $h, $metadata ) = @_;

        unless($h) {
            my $error = $metadata;
            if($error->is_fatal) {
                if($error !~ /not found/i) { # XXX is there a better way to go about this?
                    $self->log->error("An error occurred while calling get_blob: $error");
                }
            } else {
                $self->_wait_for_reconnect('_fetch_and_write_blob', $blob_name);
            }
            $on_complete->() if $on_complete;
            return;
        }

        my $revision = $metadata->{'revision'};

        my $w = $store->open_write_handle($blob);

        $h->on_read(sub {
            my $buffer = $h->rbuf;
            $h->rbuf = '';

            $w->write($buffer);
        });

        $h->on_error(sub {
            ## do something
        });

        $h->on_eof(sub {
            $w->close(sub {
                my ( $ok, $error, $conflict_file ) = @_;

                unless($ok) {
                    if($error =~ /conflict/) {
                        $self->_handle_conflict($blob, $conflict_file);
                        #
                        # XXX put revision for blobs?
                        # XXX the blob has changed since we last saw an event
                        # for it; there's probably an event in the queue.  Move
                        # $blob to a conflict file, and $conflict_file to $blob
                    } else {
                        # XXX I/O error
                    }
                }
            });
            undef $h;

            $self->_put_revision_for_blob($blob, $revision, 0);
            $on_complete->() if $on_complete;
        });
    });
}

sub _upload_blob_to_hostd {
    my ( $self, $blob_name, $on_complete ) = @_;

    my $blob = $self->store->blob(name => $blob_name);

    $self->log->info(sprintf("Sending PUT %s/blobs/%s",
        $self->upstream, $blob->name));

    my %meta;
    ## attach metadata (MIME Type, File Size, Contents Hash)

    my $revision = $self->_get_revision_for_blob($blob);
    if(defined $revision) {
        $meta{'revision'} = $revision;
    }

    $self->ws_client->put_blob($blob->name, IO::File->new($blob->path, 'r'),
        \%meta, sub {
            my ( $ws, $revision, $error ) = @_;

            if(defined $revision) {
                my $name = $blob->name;
                $self->log->info("Successfully updated $name; new revision is $revision");
                $self->_put_revision_for_blob($blob, $revision, 0);
                $on_complete->(1) if $on_complete;
            } else {
                if($error->is_fatal) {
                    # if a conflict occurs, an upstream change is coming down;
                    # we'll let them handle it
                    unless($error =~ /Conflict/) {
                        $self->log->warning("Updating $blob failed: $error");
                    }
                    $on_complete->(0) if $on_complete;
                } else {
                    $self->_wait_for_reconnect('_upload_blob_to_hostd', $blob_name);
                    $on_complete->(1) if $on_complete;
                }
            }
    });
}

sub _delete_blob_on_hostd {
    my ( $self, $blob_name, $on_complete ) = @_;

    my $blob = $self->store->blob(name => $blob_name);

    $self->log->info(sprintf("Sending DELETE %s/blobs/%s",
        $self->upstream, $blob->name));

    my $revision = $self->_get_revision_for_blob($blob);
    unless(defined $revision) {
        # this means we haven't acknowledged the file ourselves;
        # it probably was created quickly and then deleted.  Ignore it.
        $on_complete->(1) if $on_complete;
        return;
    }

    $self->ws_client->delete_blob($blob->name, $revision, sub {
        my ( $ws, $revision, $error ) = @_;

        my $name = $blob->name;
        if(defined $revision) {
            $self->log->info("Successfully deleted $name; new revision is $revision");
            $self->_put_revision_for_blob($blob, $revision, 1);
            $on_complete->(1) if $on_complete;
        } else {
            if($error->is_fatal) {
                # if a conflict occurs, an upstream change is coming down;
                # we'll let them handle it

                # ignore not found blobs (for now)
                unless($error =~ /conflict/i || $error =~ /not found/i) {
                    $self->log->warning("Deleting $name failed: $error");
                }
                $on_complete->(0) if $on_complete;
            } else {
                $self->_wait_for_reconnect('_delete_blob_on_hostd', $blob_name);
                $on_complete->(1) if $on_complete;
            }
       }
    });
}

## include hostname or something?
sub _get_conflict_blob {
    my ( $self, $blob ) = @_;

    my ( $year, $month, $day ) = (localtime)[5, 4, 3];
    $year += 1900;
    $month++;

    my $name          = $blob->name;
    my $conflict_name = sprintf("$name - conflict %04d-%02d-%02d", $year, $month, $day);
    $blob             = $self->store->blob(name => $conflict_name);

    my $counter = 1;
    while(-e $blob->path) {
        $conflict_name = sprintf("$name - conflict %04d-%02d-%02d %d", $year, $month, $day, $counter++);
        $blob          = $self->store->blob(name => $conflict_name);
    }

    return $blob;
}

# XXX move this logic into blob store (for now)
sub _handle_conflict {
    my ( $self, $blob, $conflict_file ) = @_;

    WHOA: {
        # XXX is this ok?
        if(-e $blob->path) {
            my $count = 0;
            my $target;
            while(++$count <= 5) {
                $target = $self->_get_conflict_blob($blob)->path;
                if(link $blob->path, $target) {
                    last;
                }
            }
            if($count <= 5) {
                if($conflict_file) {
                    rename $conflict_file, $blob->path;
                } else {
                    my $tempfile = File::Temp->new(DIR => $self->store->overlay, UNLINK => 0);
                    close $tempfile;

                    rename $blob->path, $tempfile->filename;
                }
                $self->handle_fs_change($self->store, {
                    blob => $self->store->blob(path => $target),
                }, sub {}); ## XXX leary...
            } else {
                $self->log->error("unable to resolve conflict");
            }
        } else {
            unless(link $conflict_file, $blob->path) {
                if($! == EEXIST) {
                    # XXX is this the right thing to do?
                    $self->_handle_conflict($blob, $conflict_file);
                } else {
                    $self->log->error("unable to resolve conflict");
                }
            }
        }
    }
}

sub handle_fs_change {
    my ( $self, $store, $event, $continuation ) = @_;

    ## if $event is just a metadata (ex. permissions) change, do something
    ## about it

    my $blob = $event->{'blob'};
    my $path = $blob->path;
    $self->log->info("$path changed on filesystem!");

    ## make sure to send blobs names in Unix style file format

    my $on_complete = sub {
        my ( $ok ) = @_;

        $continuation->() if $ok;
    };

    if(-f $path) {
        $self->_upload_blob_to_hostd($blob->name, $on_complete);
    } else {
        $self->_delete_blob_on_hostd($blob->name, $on_complete);
    }
}

sub handle_upstream_change {
    my ( $self, $change, $error ) = @_;

    unless(defined $change) {
        $self->log->warning("An error occurred while fetching changes: $error");
        return;
    }

    my $blob       = $self->store->blob(name => $change->{'name'});
    my $is_deleted = $change->{'is_deleted'};
    my $revision   = $change->{'revision'};

    $self->log->info(sprintf("Blob %s was %s on the server (revision is %s)",
        $blob->name, $is_deleted ? 'deleted' : 'changed', $revision));

    if($is_deleted) {
        $self->store->unlink($blob, sub {
            my ( $ok, $error ) = @_;

            unless($ok) {
                if($error =~ /conflict/) {
                    $self->_handle_conflict($blob);
                } else {
                    # XXX I/O error
                }
            }
        });
    } else {
        $self->_fetch_and_write_blob($blob->name);
    }

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

    my $log = $self->log;

    SaharaSync::Util->install_exception_handler(sub {
        my ( $message ) = @_;

        my $trace = longmess($message);

        $log->critical($trace);
        $log->alert($message);
    });

    mkdir $self->sync_dir unless -d $self->sync_dir;
    my $private_path = File::Spec->catfile($self->sync_dir, '.saharasync');
    mkdir $private_path unless -d $private_path;

    my $last_revision = $self->_get_last_sync;

    my $guard = $self->store->on_change(sub {
        return $self->handle_fs_change(@_);
    });

    $self->_sync_dir_guard($guard);

    $self->ws_client->changes($last_revision, [], sub {
        shift; # shift off ws_client
        return $self->handle_upstream_change(@_);
    });

    my $reconnect_timer = AnyEvent->timer(
        interval => $self->poll_interval,
        cb       => sub {
            $self->_flush_reconnect_queue;
        },
    );

    my $cond = AnyEvent->condvar;
    my $int = AnyEvent->signal(
        signal => 'INT',
        cb     => sub {
            $log->info('Received SIGINT; cleaning up and exiting');
            $cond->send;
        },
    );

    my $term = AnyEvent->signal(
        signal => 'TERM',
        cb     => sub {
            $log->info('Received SIGTERM; cleaning up and exiting');
            $cond->send;
        },
    );

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
