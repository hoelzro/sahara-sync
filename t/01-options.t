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

my @http_methods = qw(HEAD GET PUT POST DELETE);

my @tests = (
    [ '/',        [qw/HEAD/] ],
    [ '/blobs',   [qw/GET PUT DELETE/] ],
    [ '/changes', [qw/GET/] ],
);
plan tests => @tests * (@http_methods + 1);

my $app = SaharaSync::Hostd->to_app;

test_psgi app => $app, client => sub {
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