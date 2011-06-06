## no critic (RequireUseStrict)
package SaharaSync::X::InvalidArgs;

## use critic (RequireUseStrict)
use Moose;
with 'Throwable';

has message => (
    is  => 'ro',
    isa => 'Str',
);

1;

__END__

# ABSTRACT: Exception class for invalid arguments

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
