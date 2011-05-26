package SaharaSync::X::BadContext;

use Moose::Util::TypeConstraints qw(enum);
use namespace::clean;

use Moose;
with 'Throwable';

has context => (
    is  => 'ro',
    isa => enum [qw/void scalar/],
);

1;

__END__

# ABSTRACT: Exception for method calls in bad contexts.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
