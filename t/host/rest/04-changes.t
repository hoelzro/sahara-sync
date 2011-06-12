use strict;
use warnings;

use Test::Sahara ':methods', tests => 25;
use Test::JSON;
use Test::XML;
use Test::YAML::Valid;

test_host sub {
    my ( $cb ) = @_;

    my $res;

    $res = $cb->(GET '/changes');
    is $res->code, 401, "Fetching changes with no authorization should result in a 401";

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/json', 'Default return type is JSON';
    is_valid_json $res->content, 'Response body is actually JSON';

    $res = $cb->(GET_AUTHD '/changes.json', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/json', '.json return type is JSON';
    is_valid_json $res->content, 'Response body is actually JSON';

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close', Accept => 'application/json');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/json', 'Accept json return type is JSON';
    is_valid_json $res->content, 'Response body is actually JSON';

    $res = $cb->(GET_AUTHD '/changes.xml', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/xml', '.xml return type is XML';
    is_well_formed_xml $res->content, 'Response body is actually XML';

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close', Accept => 'application/xml');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/xml', 'Accept xml return type is XML';
    is_well_formed_xml $res->content, 'Response body is actually XML';

    $res = $cb->(GET_AUTHD '/changes.yml', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/x-yaml', '.yml return type is YAML';
    yaml_string_ok $res->content, 'Response body is actually YAML';

    $res = $cb->(GET_AUTHD '/changes.yaml', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/x-yaml', '.yaml return type is YAML';
    yaml_string_ok $res->content, 'Response body is actually YAML';

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close', Accept => 'application/x-yaml');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/x-yaml', 'Accept yaml return type is YAML';
    yaml_string_ok $res->content, 'Response body is actually YAML';
};

## inspect structure
## encoding
## bad Accept?
## Accept text/json?
## list Accept alternatives?
