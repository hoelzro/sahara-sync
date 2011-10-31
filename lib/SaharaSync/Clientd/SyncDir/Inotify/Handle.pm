package SaharaSync::Clientd::SyncDir::Inotify::Handle;

use strict;
use warnings;
use parent 'IO::Handle';

use Carp qw(croak);
use File::Spec;
use File::Temp;

sub new {
    my ( $class, $sync_dir, $tempfile, $mode, $destination ) = @_;

    my $self = IO::Handle::new_from_fd($class, fileno($tempfile), 'w');
    close $tempfile;
    @{*$self}{qw/tempfile mode real_name sync_dir/} =
        ( $tempfile, $mode, $destination, $sync_dir );

    return $self;
}

sub cancel {
    my ( $self ) = @_;

    my $tempfile = ${*$self}{'tempfile'};
    unlink $tempfile->filename or warn $!;
}

sub close {
    my ( $self, $cont ) = @_;

    ## the name 'real_name' sucks
    my ( $tempfile, $mode, $real_name, $sync_dir ) = @{*$self}{qw/tempfile mode real_name sync_dir/};

    my $blob_name = File::Spec->abs2rel($real_name, $sync_dir->root);
    my $retval    = IO::Handle::close($self);

    my $ok = 1;
    if(defined $mode) {
        my $temp2 = File::Temp->new(UNLINK => 0, DIR => $sync_dir->_overlay);
        close $temp2;
        rename $real_name, $temp2->filename or die $!;
        ## a user could recreate $real_name here, fucking things up.
        rename $tempfile->filename, $real_name or die $!;
        ## a user could alter $real_name here, which would cause problems
        ## if a conflict is detected.

        # XXX shitty name for a method
        unless($sync_dir->_verify_blob($blob_name, $temp2->filename)) {
            ## XXX what about hard links? (how do hard links behave with inotify?)
            rename $real_name, $tempfile->filename or die $!; ## potential problems here (could be modified)
            rename $temp2->filename, $real_name or die $!;
            $cont->(undef, 'conflict', $tempfile->filename);
            undef $ok;
            #$sync_dir->_signal_conflict($blob_name, $tempfile->filename);
        }

        chmod $mode, $real_name;
    } else {
        unless($sync_dir->_known_blob($blob_name)) {
            # XXX verify that $real_name doesn't exist
            rename $tempfile->filename, $real_name or die $!;
        } else {
            $cont->(undef, 'conflict', $tempfile->filename);
            undef $ok;
            #$sync_dir->_signal_conflict($blob_name, $tempfile->filename);
        }
    }

    $sync_dir->_update_file_stats($real_name, $blob_name);

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
