use strict;
use warnings;

use Test::Sahara ':methods', tests => 35;
use Test::JSON;
use Test::XML;
use Test::YAML::Valid;

use JSON qw(decode_json);
use YAML qw(Load);
use XML::Parser;

sub deserialize_xml
{
    my ( $s ) = @_;

    my $parser   = XML::Parser->new(Style => 'Tree');
    my $tree     = $parser->parse($s);
    my $children = $tree->[1];
    shift @$children;
    my @results;
    for(my $i = 1; $i < @$children; $i += 2) {
        my $child = $children->[$i];
        shift @$child;

        my $current = {};
        push @results, $current;
        for(my $j = 0; $j < @$child; $j += 2) {
            my ( $name, $value ) = @{$child}[$j, $j + 1];
            $value               = $value->[2];
            $current->{$name}    = $value;
        }
    }
    return \@results;
}

test_host sub {
    my ( $cb ) = @_;

    my $res;

    $res = $cb->(GET '/changes');
    is $res->code, 401, "Fetching changes with no authorization should result in a 401";

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/json', 'Default return type is JSON';
    is_valid_json $res->content, 'Response body is actually JSON';
    is_deeply decode_json($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes.json', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/json', '.json return type is JSON';
    is_valid_json $res->content, 'Response body is actually JSON';
    is_deeply decode_json($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close', Accept => 'application/json');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/json', 'Accept json return type is JSON';
    is_valid_json $res->content, 'Response body is actually JSON';
    is_deeply decode_json($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes.xml', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/xml', '.xml return type is XML';
    is_well_formed_xml $res->content, 'Response body is actually XML';
    is_deeply deserialize_xml($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close', Accept => 'application/xml');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/xml', 'Accept xml return type is XML';
    is_well_formed_xml $res->content, 'Response body is actually XML';
    is_deeply deserialize_xml($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes.yml', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/x-yaml', '.yml return type is YAML';
    yaml_string_ok $res->content, 'Response body is actually YAML';
    is_deeply Load($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes.yaml', Connection => 'close');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/x-yaml', '.yaml return type is YAML';
    yaml_string_ok $res->content, 'Response body is actually YAML';
    is_deeply Load($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close', Accept => 'application/x-yaml');
    is $res->code, 200, "Fetching changes with authorization should result in a 200";
    is $res->content_type, 'application/x-yaml', 'Accept yaml return type is YAML';
    yaml_string_ok $res->content, 'Response body is actually YAML';
    is_deeply Load($res->content), [], 'Response contains no changes';

    $res = $cb->(GET_AUTHD '/changes.foo', Connection => 'close');
    is $res->code, 406;

    $res = $cb->(GET_AUTHD '/changes', Connection => 'close', Accept => 'text/plain');
    is $res->code, 406;
};

## inspect structure
## Accept text/json?
