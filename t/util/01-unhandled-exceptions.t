use strict;
use warnings;
use parent 'Test::Class';

use AnyEvent;
use SaharaSync::Util;
use Test::More;

sub test_uncaught_exception : Test {
    my $exceptions_seen = 0;
    my $cond            = AnyEvent->condvar;

    SaharaSync::Util->install_exception_handler(sub {
        $exceptions_seen++;
    });

    my $timer1 = AnyEvent->timer(
        after => 1,
        cb    => sub {
            die "uncaught!";
        },
    );

    my $timer2 = AnyEvent->timer(
        after => 2,
        cb    => sub {
            $cond->send;
        },
    );

    $cond->recv;

    is $exceptions_seen, 1;
}

sub test_caught_exception : Test {
    my $exceptions_seen = 0;
    my $cond            = AnyEvent->condvar;

    SaharaSync::Util->install_exception_handler(sub {
        $exceptions_seen++;
    });

    my $timer1 = AnyEvent->timer(
        after => 1,
        cb    => sub {
            eval {
                die "caught!";
            };
        },
    );

    my $timer2 = AnyEvent->timer(
        after => 2,
        cb    => sub {
            $cond->send;
        },
    );

    $cond->recv;

    is $exceptions_seen, 0;
}

__PACKAGE__->runtests;
