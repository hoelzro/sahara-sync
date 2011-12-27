use strict;
use warnings;

# yo dawg, I herd you like tests, so I put a test suite in yo test suite
# so you can test while you test!

use HTTP::Request;
use LWP::UserAgent;
use Plack::Runner;
use Test::More tests => 3;
use Test::Sahara::Proxy;
use Test::TCP;

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

my $ua  = LWP::UserAgent->new;
$ua->timeout(3);
my $req = HTTP::Request->new(GET => 'http://localhost:' . $proxy->port);
my $res = $ua->request($req);

ok($res->is_success, 'going through a proxy should succeed');

$proxy->kill_connections;

$res = $ua->request($req);

ok(!$res->is_success, 'going through a deactivated proxy should fail');

$proxy->resume_connections;

$res = $ua->request($req);

ok($res->is_success, 'going through a reactivated proxy should not fail');
