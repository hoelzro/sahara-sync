use strict;
use warnings;

use Test::Deep;
use Test::More;
use Test::Sahara ':methods';
use Test::JSON;

use JSON qw(decode_json);

my $BAD_REVISON = '0' x 40;

my %types = (
    json => \&decode_json,
);

plan tests => 43 + keys(%types) * 17;

test_host sub {
    my ( $cb ) = @_;

    my $res;
    my $revision;
    my $revision2;
    my $revision3;
    my $revision4;

    $res = $cb->(GET '/changes');
    is $res->code, 401, "Fetching changes with no authorization should result in a 401";

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/json', 'Default return type is JSON';
    is $res->content_length, length($res->content), 'Content length should be present';
    is_valid_json $res->content, 'Response body is actually JSON';
    is_deeply decode_json($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes.json', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/json', '.json return type is JSON';
    is $res->content_length, length($res->content), 'Content length should be present';
    is_valid_json $res->content, 'Response body is actually JSON';
    is_deeply decode_json($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close', Accept => 'application/json');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/json', 'Accept json return type is JSON';
    is $res->content_length, length($res->content), 'Content length should be present';
    is_valid_json $res->content, 'Response body is actually JSON';
    is_deeply decode_json($res->content), [], 'Response contains no changes';

SKIP: {
    skip "XML not yet supported", 10;

    $res = $cb->(GET_AUTHD '/changes.xml', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/xml', '.xml return type is XML';
    is $res->content_length, length($res->content), 'Content length should be present';
    is_well_formed_xml($res->content, 'Response body is actually XML');
    is_deeply deserialize_xml($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close', Accept => 'application/xml');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/xml', 'Accept xml return type is XML';
    is $res->content_length, length($res->content), 'Content length should be present';
    is_well_formed_xml($res->content, 'Response body is actually XML');
    is_deeply deserialize_xml($res->content), [], 'Response contains no changes';
};

SKIP: {
    skip "YAML not yet supported", 15;

    $res = $cb->(GET_AUTHD '/changes.yml', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/x-yaml', '.yml return type is YAML';
    is $res->content_length, length($res->content), 'Content length should be present';
    yaml_string_ok($res->content, 'Response body is actually YAML');
    is_deeply Load($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes.yaml', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/x-yaml', '.yaml return type is YAML';
    is $res->content_length, length($res->content), 'Content length should be present';
    yaml_string_ok($res->content, 'Response body is actually YAML');
    is_deeply Load($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close', Accept => 'application/x-yaml');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/x-yaml', 'Accept yaml return type is YAML';
    is $res->content_length, length($res->content), 'Content length should be present';
    yaml_string_ok($res->content, 'Response body is actually YAML');
    is_deeply Load($res->content), [], 'Response contains no changes';
};

    $res = $cb->(GET_AUTHD '/changes.foo', Connection => 'close');
    is $res->code, 406;

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close', Accept => 'text/plain');
    is $res->code, 406;

    $res      = $cb->(PUT_AUTHD '/blobs/file.txt', Content => 'Test content');
    $revision = $res->header('ETag');

    foreach my $type (keys %types) {
        my $deserializer = $types{$type};
        $res             = $cb->(GET_AUTHD "/changes.$type", Connection => 'close');
        is $res->content_length, length($res->content), 'Content length should be present';
        my $changes      = $deserializer->($res->content);
        is_deeply $changes, [{ name => 'file.txt', revision => $revision }], '/changes with no last revision should return all changes';

        $res     = $cb->(GET_AUTHD "/changes.$type", Connection => 'close', 'X-Sahara-Last-Sync' => $revision);
        $changes = $deserializer->($res->content);
        is_deeply $changes, [], '/changes with the most recent last revision should return no changes';

        $res = $cb->(GET_AUTHD "/changes.$type", Connection => 'close', 'X-Sahara-Last-Sync' => $BAD_REVISON);
        is $res->code, 400, "/changes with a bad last revision should return a 400 error";
    }

    $res       = $cb->(PUT_AUTHD '/blobs/file2.txt', Content => 'Test content');
    $revision2 = $res->header('ETag');

    foreach my $type (keys %types) {
        my $deserializer = $types{$type};
        $res             = $cb->(GET_AUTHD "/changes.$type", Connection => 'close');
        is $res->content_length, length($res->content), 'Content length should be present';
        my $changes      = $deserializer->($res->content);
        cmp_bag $changes, [
            { name => 'file.txt',  revision => $revision },
            { name => 'file2.txt', revision => $revision2 },
        ], '/changes with no last revision should return all changes';

        $res     = $cb->(GET_AUTHD "/changes.$type", Connection => 'close', 'X-Sahara-Last-Sync' => $revision);
        $changes = $deserializer->($res->content);
        is_deeply $changes, [{ name => 'file2.txt', revision => $revision2 }], '/changes with a last revision should return changes since that revision';
    }

    $res      = $cb->(PUT_AUTHD '/blobs/file.txt', Content => 'More Test Content', 'If-Match' => $revision, 'X-Sahara-Value' => 17);
    $revision = $res->header('ETag');

    $res       = $cb->(DELETE_AUTHD '/blobs/file.txt', Content => 'Even More Test Content', 'If-Match' => $revision);
    $revision  = $res->header('ETag');

    $res       = $cb->(PUT_AUTHD '/blobs/file2.txt', Content => 'Test content 2', 'If-Match' => $revision2);
    $revision3 = $res->header('ETag');

    $res       = $cb->(PUT_AUTHD '/blobs/file2.txt', Content => 'Test content 3', 'If-Match' => $revision3);
    $revision4 = $res->header('ETag');

    foreach my $type (keys %types) {
        my $deserializer = $types{$type};
        $res             = $cb->(GET_AUTHD "/changes.$type", Connection => 'close');
        is $res->content_length, length($res->content), 'Content length should be present';
        my $changes      = $deserializer->($res->content);
        cmp_bag $changes, [
            { name => 'file.txt',  revision => $revision, is_deleted => 1 },
            { name => 'file2.txt', revision => $revision4 },
        ], '/changes with no last revision should return all changes' or diag(explain($changes));

        $res     = $cb->(GET_AUTHD "/changes.$type", Connection => 'close', 'X-Sahara-Last-Sync' => $revision2);
        is $res->content_length, length($res->content), 'Content length should be present';
        $changes = $deserializer->($res->content);
        is_deeply $changes, [{
            name       => 'file.txt',
            revision   => $revision,
            is_deleted => 1
        }, {
            name     => 'file2.txt',
            revision => $revision4,
        }], '/changes with a last revision should return changes since that revision';

        $res = $cb->(GET_AUTHD "/changes.$type", Connection => 'close', 'X-Sahara-Last-Sync' => $revision);
        is $res->content_length, length($res->content), 'Content length should be present';
        $changes = $deserializer->($res->content);
        is_deeply $changes, [{
            name     => 'file2.txt',
            revision => $revision4,
        }], '/changes with a last revision should return changes since that revision';

        $res     = $cb->(GET_AUTHD "/changes.$type?metadata=value", Connection => 'close');
        is $res->content_length, length($res->content), 'Content length should be present';
        $changes = $deserializer->($res->content);
        cmp_bag $changes, [
            { name => 'file.txt',  revision => $revision, value => 17, is_deleted => 1 },
            { name => 'file2.txt', revision => $revision4 },
        ], '/changes with a metadata query param should fetch that metadata';

        $res = $cb->(GET_AUTHD "/changes.$type?metadata=value", Connection => 'close', 'X-Sahara-Last-Sync' => $revision2);
        is $res->content_length, length($res->content), 'Content length should be present';
        $changes = $deserializer->($res->content);
        is_deeply $changes, [{
            name       => 'file.txt',
            revision   => $revision,
            is_deleted => 1,
            value      => 17,
        }, {
            name     => 'file2.txt',
            revision => $revision4,
        }], '/changes with a last revision should return changes since that revision';
    }
};

## Accept text/json?
