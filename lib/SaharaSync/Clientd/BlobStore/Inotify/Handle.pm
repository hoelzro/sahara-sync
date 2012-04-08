package SaharaSync::Clientd::BlobStore::Inotify::Handle;

use strict;
use warnings;
use parent 'IO::Handle';

use Carp qw(croak);
use File::Temp;

sub new {
    my ( $class, $store, $tempfile, $mode, $blob ) = @_;

    my $self = IO::Handle::new_from_fd($class, fileno($tempfile), 'w');
    close $tempfile;
    @{*$self}{qw/tempfile mode blob store/} =
        ( $tempfile, $mode, $blob, $store );

    return $self;
}

sub cancel {
    my ( $self ) = @_;

    my $tempfile = ${*$self}{'tempfile'};
    unlink $tempfile->filename or warn $!;
}

sub close {
    my ( $self, $cont ) = @_;

    my ( $tempfile, $mode, $blob, $store ) = @{*$self}{qw/tempfile mode blob store/};

    my $retval    = IO::Handle::close($self);

    my $ok = 1;
    if(defined $mode) {
        my $temp2 = File::Temp->new(UNLINK => 0, DIR => $store->overlay);
        close $temp2;
        rename $blob->path, $temp2->filename or die $!;
        ## a user could recreate $blob->path here, fucking things up.
        rename $tempfile->filename, $blob->path or die $!;
        ## a user could alter $blob->path here, which would cause problems
        ## if a conflict is detected.

        # XXX shitty name for a method
        unless($store->verify_blob($blob, $temp2->filename)) {
            ## XXX what about hard links? (how do hard links behave with inotify?)
            rename $blob->path, $tempfile->filename or die $!; ## potential problems here (could be modified)
            rename $temp2->filename, $blob->path or die $!;
            $cont->(undef, 'conflict', $tempfile->filename);
            undef $ok;
            #$store->_signal_conflict($blob->name, $tempfile->filename);
        }

        chmod $mode, $blob->path;
    } else {
        unless($store->is_known_blob($blob)) {
            # XXX verify that $blob->path doesn't exist
            rename $tempfile->filename, $blob->path or die $!;
        } else {
            $cont->(undef, 'conflict', $tempfile->filename);
            undef $ok;
            #$store->_signal_conflict($blob->name, $tempfile->filename);
        }
    }

    $store->update_file_stats($blob);

    croak "Continuation needed" unless $cont;
    $cont->($ok) if $ok;

    return $retval;
}

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
