use strict;
use warnings;

# yo dawg, I herd you like tests, so I put a test suite in yo test suite
# so you can test while you test!

use AnyEvent::HTTP;
use Plack::Runner;
use Test::More tests => 3;
use Test::Sahara::Proxy;
use Test::TCP;

sub do_request {
    my ( $url ) = @_;

    my $cond  = AnyEvent->condvar;
    my $headers;

    http_get $url, timeout => 3, sub {
        ( undef, $headers ) = @_;

        $cond->send;
    };

    $cond->recv;

    return $headers->{'Status'};
}

my $psgi_app = sub {
    my ( $env ) = @_;

    return [
        200,
        ['Content-Type' => 'text/plain'],
        ['OK'],
    ];
};

my $server = Test::TCP->new(
    code => sub {
        my ( $port ) = @_;

        my $runner = Plack::Runner->new;
        $runner->parse_options(
            "--port=$port",
            '--env=deployment',
            '--host=127.0.0.1',
        );
        $runner->run($psgi_app);
    },
);

my $proxy = Test::Sahara::Proxy->new(remote => $server->port);
my $url   = 'http://localhost:' . $proxy->port;
my $status;

$status = do_request($url);
is $status, 200, 'going through a proxy should succeed';

$proxy->kill_connections;

$status = do_request($url);

isnt $status, 200, 'going through a deactivated proxy should fail';

$proxy->resume_connections;

$status = do_request($url);

is $status, 200, 'going through a reactivated proxy should not fail';
