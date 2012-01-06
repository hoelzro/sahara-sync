package AnyEvent::WebService::Sahara::Error;

use strict;
use warnings;

use overload
    '""' => \&message;

sub new {
    my ( $class, %params ) = @_;

    return bless {
        code    => $params{'code'},
        message => $params{'message'},
    }, $class;
}

sub is_fatal {
    my ( $self ) = @_;

    my $code = $self->{'code'};

    return $code >= 400 &&
           $code <  500;
}

sub message {
    my ( $self ) = @_;

    return $self->{'message'};
}

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
