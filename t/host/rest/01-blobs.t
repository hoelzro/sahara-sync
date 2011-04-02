use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";

use Test::Sahara ':methods', tests => 15;

test_host sub {
    my ( $cb ) = @_;

    my $res;

    $res = $cb->(GET '/blobs/test.txt');
    is $res->code, 401;

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 404;

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt');
    is $res->code, 404;

    $res = $cb->(PUT_AUTHD 'http://localhost:5000/blobs/test.txt', Content => 'Hello, World!');
    is $res->code, 201;
    is $res->header('Location'), 'http://localhost:5000/blobs/test.txt';

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 200;
    is $res->content, 'Hello, World!';

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt');
    is $res->code, 200;

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 404;

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt');
    is $res->code, 404;

    $res = $cb->(PUT_AUTHD 'http://localhost:5000/blobs/test.txt', Content => 'Hello, World!');
    is $res->code, 201;
    is $res->header('Location'), 'http://localhost:5000/blobs/test.txt';

    $res = $cb->(PUT_AUTHD '/blobs/test.txt', Content => 'Hello, World (again)');
    is $res->code, 200;

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 200;
    is $res->content, 'Hello, World (again)';

    $cb->(DELETE_AUTHD '/blobs/test.txt'); # clean up (we should avoid this kind of stuff in the future)
};
