use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";

use HTTP::Request;
use MIME::Base64 qw(encode_base64);
use Test::Sahara tests => 16;

sub REQUEST {
    my ( $method, $path, %headers ) = @_;

    $headers{'Authorization'} = 'Basic ' . encode_base64('test:abc123');

    my $content = delete $headers{'Content'};
    my $req     = HTTP::Request->new($method, $path);
    foreach my $k (keys %headers) {
        $req->header($k, $headers{$k});
    }
    if(defined $content) {
        $req->content($content);
    }

    return $req;
}

sub GET {
    return REQUEST(GET => @_);
}

sub PUT {
    return REQUEST(PUT => @_);
}

sub DELETE {
    return REQUEST(DELETE => @_);
}

test_host sub {
    my ( $cb ) = @_;

    my $res;

    $res = $cb->(HTTP::Request->new(GET => '/blobs/test.txt'));
    is $res->code, 401;

    $res = $cb->(GET '/blobs/test.txt');
    is $res->code, 404;

    $res = $cb->(DELETE '/blobs/test.txt');
    is $res->code, 404;

    $res = $cb->(PUT '/blobs/test.txt', Content => 'Hello, World!');
    is $res->code, 201;
    is $res->header('Location'), 'http://localhost:5000/blobs/test.txt';

    $res = $cb->(GET '/blobs/test.txt');
    is $res->code, 200;
    is $res->content, 'Hello, World!';

    $res = $cb->(DELETE '/blobs/test.txt');
    is $res->code, 200;

    $res = $cb->(GET '/blobs/test.txt');
    is $res->code, 404;

    $res = $cb->(DELETE '/blobs/test.txt');
    is $res->code, 404;

    $res = $cb->(PUT '/blobs/test.txt', Content => 'Hello, World!');
    is $res->code, 201;
    is $res->header('Location'), 'http://localhost:5000/blobs/test.txt';

    $res = $cb->(PUT '/blobs/test.txt', Content => 'Hello, World (again)');
    is $res->code, 200;

    $res = $cb->(GET '/blobs/test.txt');
    is $res->code, 200;
    is $res->content, 'Hello, World (again)';

    $cb->(DELETE '/blobs/test.txt'); # clean up (we should avoid this kind of stuff in the future)
};

pass;
