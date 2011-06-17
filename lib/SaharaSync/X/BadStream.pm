## no critic (RequireUseStrict)
package SaharaSync::X::BadStream;

## use critic (RequireUseStrict)
use Moose;

with 'Throwable';

has message => (
    is  => 'ro',
    isa => 'Str',
);

1;

# ABSTRACT: Exception for stream parser errors.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
