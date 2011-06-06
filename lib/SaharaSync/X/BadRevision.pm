## no critic (RequireUseStrict)
package SaharaSync::X::BadRevision;

## use critic (RequireUseStrict)
use Moose;
with 'Throwable';

has revision => (
    is  => 'ro',
    isa => 'Str',
);

1;

__END__

# ABSTRACT: Exception class for bad revision specifications.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
