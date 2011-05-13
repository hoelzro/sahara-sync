use strict;
use warnings;

use Test::Sahara ':methods', tests => 45;

my $BAD_REVISION = '0' x 64;

test_host sub {
    my ( $cb ) = @_;

    my $res;
    my $last_revision;

    $res = $cb->(GET '/blobs/test.txt');
    is $res->code, 401, "Fetching a blob with no authorization should result in a 401";

    $res = $cb->(HEAD '/blobs/test.txt');
    is $res->code, 401, "Using the HEAD method with no authorization should result in a 401";

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 404, "Fetching a non-existent blob should result in a 404";

    $res = $cb->(HEAD_AUTHD '/blobs/test.txt');
    is $res->code, 404, "Using the HEAD method on a non-existent blob should result in a 404";

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt');
    is $res->code, 400, "Attempting a delete operation without a revision should result in a 400";

    $res = $cb->(PUT_AUTHD 'http://localhost:5000/blobs/test.txt', Content => 'Hello, World!', 'If-Match' => $BAD_REVISION);
    is $res->code, 400, "Attempting to create a blob and specifying a revision should result in a 400";

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 404, "Fetching a non-existent blob should result in a 404";

    $res = $cb->(PUT_AUTHD 'http://localhost:5000/blobs/test.txt', Content => 'Hello, World!');
    is $res->code, 201, "Creating a new blob with no revision specified should result in a 201";
    is $res->header('Location'), 'http://localhost:5000/blobs/test.txt', "Creating a new blob should yield the Location header";
    $last_revision = $res->header('ETag');
    ok $last_revision, "A successful put operation should yield the ETag header";

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 200, "Fetching an existent blob should result in a 200";
    is $res->content, 'Hello, World!', "The contents of an existent blob should match its last PUT";
    is $res->header('ETag'), $last_revision, "The ETag of an existent blob should match the one returned from its last PUT";

    $res = $cb->(HEAD_AUTHD '/blobs/test.txt');
    is $res->code, 200, "Using the HEAD method on an existing blob should result in a 200";
    is $res->header('ETag'), $last_revision, "The ETag of an exisent blob should match the one returned from its last PUT";

    $res = $cb->(GET_AUTHD '/blobs/test.txt', 'If-None-Match' => $last_revision);
    is $res->code, 304, "Conditional GET of an unmodified blob should result in a 304";
    is $res->content, '', "Conditional GET of an unmodified blob should yield no body";

    $res = $cb->(HEAD_AUTHD '/blobs/test.txt', 'If-None-Match' => $last_revision);
    is $res->code, 304, "Conditional HEAD of an unmodified blob should result in a 304";

    $res = $cb->(GET_AUTHD '/blobs/test.txt', 'If-None-Match' => $BAD_REVISION);
    is $res->code, 200, "Conditional GET of a modified blob should result in a 200";
    is $res->content, 'Hello, World!', "Conditional GET of a modified blob should yield that blob's body";
    is $res->header('ETag'), $last_revision, "Conditional GET of a modified blob should yield its ETag";

    $res = $cb->(HEAD_AUTHD '/blobs/test.txt', 'If-None-Match' => $BAD_REVISION);
    is $res->code, 200, "Conditional HEAD of a modified blob should result in a 200";
    is $res->header('ETag'), $last_revision, "Conditional HEAD of a modified blob should yield its ETag";

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt');
    is $res->code, 400, "Attemping a delete operation on a blob without a revision should result in a 400";

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt', 'If-Match' => $BAD_REVISION);
    is $res->code, 409, "Attemping a delete operation with a non-matching revision should result in a 409";

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt', 'If-Match' => $last_revision);
    is $res->code, 200, "Deleting a blob with the correct revision should result in a 200";

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 404, "Fetching a blob that has been deleted should result in a 404";

    $res = $cb->(HEAD_AUTHD '/blobs/test.txt');
    is $res->code, 404, "Using the HEAD method on a blob that has been deleted should result in a 404";

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt');
    is $res->code, 400, "Attemping a delete operation without revision info should result in a 400";;

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt', 'If-Match' => $BAD_REVISION);
    is $res->code, 404, "Attempting to delete a non-existent blob should result in a 404";

    $res = $cb->(DELETE_AUTHD '/blobs/test.txt', 'If-Match' => $last_revision);
    is $res->code, 404, "Attempting to delete a non-existent blob should result in a 404";

    $res = $cb->(PUT_AUTHD 'http://localhost:5000/blobs/test.txt', Content => 'Hello, World!', 'If-Match' => $BAD_REVISION);
    is $res->code, 400, "Attempting to create a blob and specifying a revision should result in a 400";

    $res = $cb->(PUT_AUTHD 'http://localhost:5000/blobs/test.txt', Content => 'Hello, World!', 'If-Match' => $last_revision);
    is $res->code, 400, "Attempting to create a blob and specifying a revision should result in a 400";

    $res = $cb->(PUT_AUTHD 'http://localhost:5000/blobs/test.txt', Content => 'Hello, World!');
    is $res->code, 201, "Creating a new blob should result in a 201";
    is $res->header('Location'), 'http://localhost:5000/blobs/test.txt', "Creating a resource should yield the Location header";
    my $previous_revision = $last_revision;
    $last_revision = $res->header('ETag');
    ok $last_revision, "Creating a resource should yield its ETag";

    $res = $cb->(PUT_AUTHD '/blobs/test.txt', Content => 'Hello, World (again)');
    is $res->code, 400, "Writing to an existing resource without revision information should result in a 400";

    $res = $cb->(PUT_AUTHD '/blobs/test.txt', Content => 'Hello, World (again)', 'If-Match' => $previous_revision);
    is($res->code, 409, "Writing to an existing resource with a non-matching revision should result in a 409") || diag($res->content);

    $res = $cb->(PUT_AUTHD '/blobs/test.txt', Content => 'Hello, World (again)', 'If-Match' => $last_revision);
    is $res->code, 200, "Writing to an existing resource with a matching revision should result in a 200";
    $last_revision = $res->header('ETag');
    ok $last_revision, "A successful write should yield the ETag header";

    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 200, "Fetching an existent blob should result in a 200";
    is $res->content, 'Hello, World (again)', "The contents for an existent blob should match its last PUT";
    is $res->header('ETag'), $last_revision, "Fetching an existent blob should yield the ETag header";

    $res = $cb->(HEAD_AUTHD '/blobs/test.txt');
    is $res->code, 200, "The HEAD method should result in a 200 when called on an existent blob";
    is $res->header('ETag'), $last_revision, "The HEAD method should yield the ETag header when called on an existent blob";

    $cb->(DELETE_AUTHD '/blobs/test.txt', 'If-Match' => $last_revision); # clean up (we should avoid this kind of stuff in the future)
};
