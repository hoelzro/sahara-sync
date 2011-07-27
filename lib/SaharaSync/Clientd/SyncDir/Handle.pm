package SaharaSync::Clientd::SyncDir::Handle;

use strict;
use warnings;
use parent 'IO::Handle';

sub new {
    my ( $class, $tempfile, $mode, $destination ) = @_;

    my $self = IO::Handle::new_from_fd($class, fileno($tempfile), 'w');
    @{*$self}{qw/temp_name mode real_name/} =
        ( $tempfile->filename, $mode, $destination );
    return $self;
}

sub cancel {
    my ( $self ) = @_;

    my ( $temp_name ) = ${*$self}{'temp_name'};
    unlink $temp_name or warn $!;
}

sub close {
    my ( $self ) = @_;

    my ( $temp_name, $mode, $real_name ) = @{*$self}{qw/temp_name mode real_name/};

    my $retval = IO::Handle::close($self);
    chmod $mode, $temp_name or die $! if defined $mode;
    rename $temp_name, $real_name or die $!;

    return $retval;
}

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
