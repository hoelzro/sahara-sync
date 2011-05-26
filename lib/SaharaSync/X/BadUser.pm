package SaharaSync::X::BadUser;

use Moose;
with 'Throwable';

has username => (
    is  => 'ro',
    isa => 'Str',
);

1;

__END__

# ABSTRACT: Exception class for bad users

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
