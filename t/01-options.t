use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use HTTP::Request;
use Test::Deep;
use Test::More;
use SaharaSync::Hostd;
use Plack::Test;

sub OPTIONS {
    my ( $path ) = @_;

    return HTTP::Request->new(OPTIONS => $path);
}

my @tests = (
    [ '/',        [qw/HEAD/] ],
    [ '/blobs',   [qw/GET PUT DELETE/] ],
    [ '/changes', [qw/GET/] ],
);
plan tests => scalar(@tests);

my $app = SaharaSync::Hostd->to_app;

test_psgi app => $app, client => sub {
    my ( $cb ) = @_;

    foreach my $test (@tests) {
        my ( $path, $methods ) = @$test;

        my $res = $cb->(OPTIONS $path);
        my @allowed = split /[,\s]+/, $res->header('Allow');
        cmp_bag(\@allowed, $methods, "Checking OPTIONS for $path");
    }
};
