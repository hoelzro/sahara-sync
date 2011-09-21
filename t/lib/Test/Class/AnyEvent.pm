package Test::Class::AnyEvent;

use strict;
use warnings;
use parent 'Test::Class';

use EV;
use Test::More;

my %timeouts;

sub TIMEOUT {
    my $self  = shift;
    my $class = ref($self) || $self;

    if(@_) {
        $timeouts{$class} = shift;
    }
    return $timeouts{$class} || 30;
}

sub setup_kill_timeout :Test(setup) {
    my ( $self ) = @_;

    $self->{'kill_timer'} = AnyEvent->timer(
        after => $self->TIMEOUT,
        cb    => sub {
            diag "Your test took too long!";
            exit 1;
        },
    );
}

sub stop_kill_timeout :Test(teardown) {
    my ( $self ) = @_;

    delete $self->{'kill_timer'};
}

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
