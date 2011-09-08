package SaharaSync::Clientd::SyncDir::Inotify::Handle;

use strict;
use warnings;
use parent 'IO::Handle';

use File::Spec;

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
    my ( $self ) = @_;

    my ( $tempfile, $mode, $real_name, $sync_dir ) = @{*$self}{qw/tempfile mode real_name sync_dir/};

    my $retval = IO::Handle::close($self);
    chmod $mode, $tempfile->filename or die $! if defined $mode;
    rename $tempfile->filename, $real_name or die $!;

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
