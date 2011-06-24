use strict;
use warnings;

use Test::Builder;
use Test::Deep::NoTest qw(cmp_details deep_diag);
use Test::Sahara ':methods', tests => 3;

sub metadata_ok {
    my ( $res, $expected, $name ) = @_;

    my $tb = Test::Builder->new;

    my $actual = {};
    my @names = grep { /^x-sahara-/i } $res->header_field_names;
    foreach my $name (@names) {
        my $value     = $res->header($name);
        my $meta_name = $name;
        $meta_name    =~ s/^x-sahara-//i;

        $actual->{lc $meta_name} = $value;
    }

    my ( $ok, $stack ) = cmp_details($actual, $expected);
    $tb->ok($ok, $name) || diag(deep_diag($stack));
}

test_host sub {
    my ( $cb ) = @_;

    my $res;

    $res = $cb->(PUT_AUTHD '/blobs/test.txt', Content => 'Test content',
        'X-SAHARA-FOOBAR' => 18192);
    is $res->code, 201;
    $res = $cb->(GET_AUTHD '/blobs/test.txt');
    is $res->code, 200;
    metadata_ok($res, { foobar => 18192 }, "Metadata passed in via all-caps headers should persist");
};
