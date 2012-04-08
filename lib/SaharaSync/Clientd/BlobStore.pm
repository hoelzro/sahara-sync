package SaharaSync::Clientd::BlobStore;

use Moose;
use feature 'switch';

__PACKAGE__->meta->make_immutable;

sub create {
    my ( $class, %args ) = @_;

    given($^O) {
        when('linux') {
            require SaharaSync::Clientd::BlobStore::Inotify;

            return SaharaSync::Clientd::BlobStore::Inotify->new(%args);
        }
        default {
            return;
        }
    }
}

1;

__END__

# ABSTRACT: Blob storage objects

=head1 SYNOPSIS

=head1 DESCRIPTION

Sync dir objects are responsible for abstracting the messy details of
maintaining a synchronized directory away from the client daemon
implementation.  They have several responsibilities:

=head2 CHANGE NOTIFICATIONS

Implementations are responsible for presenting a unified interface to their
operating system's filesystem change notification API.  In addition, the
change notifications must have the following properties:

=head3 FINE-GRAINED

Events delivered through the sync dir API must apply to individual files
in a sync dir.

=head3 OFFLINE

Implementations must report events that occurred when the client daemon is
not running.  For example, if a file is changed before the daemon is started.
Implementations are not required to report events that are undetectable (ex.
if I add a file and then remove it, then start up the daemon).

=head3 EXTERNAL

Implementations must only report externally-generated events; meaning events
that the sync dir itself did not generate.

=head2 TRANSACTIONAL SEMANTICS

Implementations are responsible for adding transactional support for modifying
files.

=head2 CONFLICT NOTIFICATIONS

Implementations are responsible for notifying interested parties about
conflicts.

=head2 FILESYSTEM API

Implementations are responsible for exposing a filesystem API that adds the
transactional semantics mentioned above, as well as to distinguish internal
from external events.

=head1 IMPLEMENTATION CONSTRAINTS

=over

=item Implementations are not required to pick up events under "strange" circumstances; ex.
if a user boots into a live CD environment, mounts the partition in which the sync dir resides,
and changes files there. (This makes me wonder...have a "hard" check fire every so often?)


=item Implementations are free to constrain users to particular filesystems, but within reason. ex. a Windows implementation
can restrict users to NTFS.

=back

=head1 FUNCTIONS

=cut
