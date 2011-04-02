use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";

use Test::Deep;
use Test::Sahara ':methods';

my @http_methods = qw(HEAD GET PUT POST DELETE);

my @tests = (
    [ '/',        [qw/HEAD/] ],
    [ '/blobs',   [qw/GET PUT DELETE/] ],
    [ '/changes', [qw/GET/] ],
);
plan tests => @tests * (@http_methods + 1);

test_host sub {
    my ( $cb ) = @_;

    foreach my $test (@tests) {
        my ( $path, $methods ) = @$test;

        my $res = $cb->(OPTIONS $path);
        my @allowed = split /[,\s]+/, $res->header('Allow');
        cmp_bag(\@allowed, $methods, "Checking OPTIONS for $path");

        my %allowed = map { $_ => 1 } @allowed;
        foreach my $method (@http_methods) {
            if($allowed{$method}) {
                # we don't want to touch the server, so just pass
                pass "Passing with good method";
            } else {
                $res = $cb->(HTTP::Request->new($method, $path));
                is $res->code, 405, "Verifying that $method is not allowing on $path";
            }
        }
    }
};
