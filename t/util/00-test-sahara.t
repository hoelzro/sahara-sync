use strict;
use warnings;

use Plack::Test;
use Test::More tests => 3;
use Test::Sahara ':methods';

my $streaming_app      = Test::Sahara->create_fresh_app; # defaults to streaming
my $also_streaming_app = Test::Sahara->create_fresh_app(
    server => {
        disable_streaming => 0,
    },
);
my $nonstreaming_app   = Test::Sahara->create_fresh_app(
    server => {
        disable_streaming => 1,
    },
);

$Plack::Test::Impl = 'AnyEvent';

test_psgi $streaming_app, sub {
    my ( $cb ) = @_;

    my $res = $cb->(HEAD '/');
    is $res->header('X-Sahara-Capabilities'), 'streaming';
};

test_psgi $also_streaming_app, sub {
    my ( $cb ) = @_;

    my $res = $cb->(HEAD '/');
    is $res->header('X-Sahara-Capabilities'), 'streaming';
};

test_psgi $nonstreaming_app, sub {
    my ( $cb ) = @_;

    my $res = $cb->(HEAD '/');
    is $res->header('X-Sahara-Capabilities'), '';
};
