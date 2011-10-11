use strict;
use warnings;

use Test::More;
use Plack::Test::Suite;
use SaharaSync::Hostd::Server;
use Test::TCP qw(empty_port);
use AnyEvent::HTTP;

Plack::Test::Suite->run_server_tests('SaharaSync');

my $port   = empty_port;
my $server = SaharaSync::Hostd::Server->new(
    port => $port,
    host => '127.0.0.1',
);

my $app = sub {
    return [
        200,
        ['Content-Type' => 'text/plain'],
        ['OK'],
    ];
};

$server->start($app);

my $cond = AnyEvent->condvar;

http_get 'http://localhost:' . $port, sub {
    my ( $data, $headers ) = @_;

    ok $headers->{'Status'} < 400;
    $cond->send;
};

$cond->recv;

$server->stop;

done_testing;
