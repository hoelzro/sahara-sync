use strict;
use warnings;

# yo dawg, I herd you like tests, so I put a test suite in yo test suite
# so you can test while you test!

use AnyEvent::HTTP;
use Plack::Builder;
use Plack::Runner;
use Time::HiRes qw(usleep);
use Test::More tests => 5;
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

my $non_streaming = sub {
    my ( $env ) = @_;

    return [
        200,
        ['Content-Type' => 'text/plain'],
        ['OK'],
    ];
};

my $streaming = sub {
    my ( $env ) = @_;

    return sub {
        my ( $respond ) = @_;

        my $writer = $respond->( [200, ['Content-Type' => 'text/plain'] ]);

        foreach my $number ( 1 .. 10 ) {
            $writer->write($number . "\n");
            usleep 100_000;
        }
    };
};

my $psgi_app = builder {
    mount '/streaming' => $streaming;
    mount '/'          => $non_streaming;
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

my @lines;
my $cond = AnyEvent->condvar;
http_get "$url/streaming", timeout => 3, want_body_handle => 1, sub {
    my ( $h, $headers ) = @_;

    is $headers->{'Status'}, 200, 'streaming response should succeed';

    $h->on_read(sub {
        $h->push_read(line => sub {
            my ( undef, $line ) = @_;

            push @lines, $line;
        });
    });

    $h->on_error(sub {
        my ( undef, undef, $error ) = @_;

        fail "Unexpected error: $error";
        $h->destroy;
        $cond->send;
    });

    $h->on_eof(sub {
        $h->destroy;
        $cond->send;
    });
};
$cond->recv;

is_deeply \@lines, [ 1 .. 10 ], 'streaming response contents should be ok';
