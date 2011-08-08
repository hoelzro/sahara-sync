use strict;
use warnings;

use MIME::Base64 ();

use Test::More tests => 4;
use Test::Sahara ':methods';

sub generate_authorization {
    my ( undef, $username, $password ) = @_;

    return 'Basic ' . MIME::Base64::encode_base64(
        $username . ':' . $password, '');
}

test_host sub {
    my ( $cb ) = @_;

    my $res;

    $res = $cb->(GET '/blobs/test.txt');
    is $res->code, 401, "Fetching a blob with no authorization data should result in a 401";

    $res = $cb->(GET '/blobs/test.txt',
        Authorization => generate_authorization($res, 'test', 'abc123'));
    is $res->code, 404, "Fetching a non-existent blob with correct auth data should result in a 404";

    $res = $cb->(GET '/blobs/test.txt',
        Authorization => generate_authorization($res, 'test', 'abc124'));
    is $res->code, 401, "Fetching a non-existent blob with incorrect auth data should result in a 401";

    $res = $cb->(GET '/blobs/test.txt',
        Authorization => generate_authorization($res, 'test2', 'abc123'));
    is $res->code, 401, "Fetching a non-existent blob with incorrect auth data should result in a 401";
};
