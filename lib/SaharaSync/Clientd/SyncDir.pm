package SaharaSync::Clientd::SyncDir;

use Moose;
use feature 'switch';

__PACKAGE__->meta->make_immutable;

sub create_syncdir {
    my ( $class, %args ) = @_;

    given($^O) {
        when('linux') {
            require SaharaSync::Clientd::SyncDir::Inotify;

            return SaharaSync::Clientd::SyncDir::Inotify->new(%args);
        }
        default {
            return;
        }
    }
}

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
