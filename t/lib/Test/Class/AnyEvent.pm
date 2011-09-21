package Test::Class::AnyEvent;

use strict;
use warnings;
use parent 'Test::Class';

use EV;
use Test::More;

sub setup_error_handler :Test(setup) {
    my ( $self ) = @_;

    $self->{'error'} = 0;

    $EV::DIED = sub {
        $self->{'error'} = 1;
        note($@);
    };
}

sub check_error_handler :Test(teardown => 1) {
    my ( $self ) = @_;

    is $self->{'error'}, 0, "No uncaught errors should occur during testing";
}

__PACKAGE__->SKIP_CLASS(1);

1;
