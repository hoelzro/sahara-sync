package SaharaSync::Clientd::SyncDir::Inotify::Handle;

use strict;
use warnings;
use parent 'IO::Handle';

use File::Spec;

sub new {
    my ( $class, $sync_dir, $tempfile, $mode, $destination ) = @_;

    my $self = IO::Handle::new_from_fd($class, fileno($tempfile), 'w');
    @{*$self}{qw/temp_name mode real_name sync_dir/} =
        ( $tempfile->filename, $mode, $destination, $sync_dir );
    return $self;
}

sub cancel {
    my ( $self ) = @_;

    my ( $temp_name ) = ${*$self}{'temp_name'};
    unlink $temp_name or warn $!;
}

sub close {
    my ( $self ) = @_;

    my ( $temp_name, $mode, $real_name, $sync_dir ) = @{*$self}{qw/temp_name mode real_name sync_dir/};

    my $retval = IO::Handle::close($self);
    chmod $mode, $temp_name or die $! if defined $mode;
    rename $temp_name, $real_name or die $!;

    my $file = File::Spec->abs2rel($real_name, $sync_dir->root);
    $sync_dir->_update_file_stats($real_name, $file);

    return $retval;
}

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
