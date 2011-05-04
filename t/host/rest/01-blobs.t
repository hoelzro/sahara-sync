use strict;
use warnings;

use Test::Sahara ':methods', tests => 15;

test_host sub {
    my ( $cb ) = @_;

    my $res;

    $res = $cb->(GET '/blobs/test.txt');
    is $res->code, 401, "Fetching a blob with no authorization should result in a 401";

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 404, "Fetching a non-existent blob should result in a 404";

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt');
    is $res->code, 404, "Deleting a non-existent blob should result in a 404";

    $res = $cb->(PUT_AUTHD 'http://localhost:5000/blobs/test.txt', Content => 'Hello, World!');
    is $res->code, 201, "Creating a new blob should result in a 201";
    is $res->header('Location'), 'http://localhost:5000/blobs/test.txt', "Creating a resource should yield the Location header";

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 200, "Fetching an existent blob should result in a 200";
    is $res->content, 'Hello, World!', "The contents for an existent blob should match its last PUT";

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt');
    is $res->code, 200, "Deleting an existent blob should succeed";

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 404, "Fetching a blob that has been deleted should result in a 404";

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt');
    is $res->code, 404, "Deleting a blob that has already been deleted should result in a 404";

    $res = $cb->(PUT_AUTHD 'http://localhost:5000/blobs/test.txt', Content => 'Hello, World!');
    is $res->code, 201, "Creating a new blob should result in a 201";
    is $res->header('Location'), 'http://localhost:5000/blobs/test.txt', "Creating a resource should yield the Location header";

    $res = $cb->(PUT_AUTHD '/blobs/test.txt', Content => 'Hello, World (again)');
    is $res->code, 200, "Writing to an existing resource should result in a 200";

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 200, "Fetching an existent blob should result in a 200";
    is $res->content, 'Hello, World (again)', "The contents for an existent blob should match its last PUT";

    $cb->(DELETE_AUTHD '/blobs/test.txt'); # clean up (we should avoid this kind of stuff in the future)
};
