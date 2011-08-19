use strict;
use warnings;
use parent 'Test::Class';

use AnyEvent;
use HTTP::Request::Common;
use LWP::UserAgent;
use Plack::Runner;
use SaharaSync::Util;
use Test::More;
use Test::TCP qw(test_tcp);

sub test_uncaught_exception : Test {
    my $exceptions_seen = 0;
    my $cond            = AnyEvent->condvar;

    note($AnyEvent::MODEL);

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

sub test_uncaught_exception_psgi : Test {
    my $pid = $$;
    
    # we do this by hand because we need to set up
    # signal handlers and such
    test_tcp(
        client => sub {
            my ( $port ) = @_;

            my $exception_seen;

            local $SIG{USR1} = sub {
                $exception_seen = 1;
            };

            my $ua = LWP::UserAgent->new;
            $ua->request(GET "http://localhost:$port/");

            ok $exception_seen;
        },
        server => sub {
            my ( $port ) = @_;

            SaharaSync::Util->install_exception_handler(sub {
                kill USR1 => $pid;
            });

            my $app = sub {
                die "uncaught!";
            };

            my $runner = Plack::Runner->new;
            $runner->parse_options("--port=$port", '--env=deployment');
            $runner->run($app);
        },
    );
}

sub test_caught_exception_psgi : Test {
    my $pid = $$;
    
    # same as above...
    test_tcp(
        client => sub {
            my ( $port ) = @_;

            my $exception_seen;

            local $SIG{USR1} = sub {
                $exception_seen = 1;
            };

            my $ua = LWP::UserAgent->new;
            $ua->request(GET "http://localhost:$port/");

            ok ! $exception_seen;
        },
        server => sub {
            my ( $port ) = @_;

            SaharaSync::Util->install_exception_handler(sub {
                kill USR1 => $pid;
            });

            my $app = sub {
                eval {
                    die "caught!";
                };

                return [
                    200,
                    ['Content-Type' => 'text/plain'],
                    ['ok'],
                ];
            };

            my $runner = Plack::Runner->new;
            $runner->parse_options("--port=$port", '--env=deployment');
            $runner->run($app);
        },
    );
}

__PACKAGE__->runtests;
