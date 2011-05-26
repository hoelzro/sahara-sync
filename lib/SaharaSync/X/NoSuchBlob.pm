package SaharaSync::X::NoSuchBlob;

use Moose;
with 'Throwable';

has blob => (
    is  => 'ro',
    isa => 'Str',
);

1;

__END__

# ABSTRACT: Exception class for non-existent blobs

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
