use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use HTTP::Request::Common;
use Test::Sahara tests => 1;

test_host sub {
    my ( $cb ) = @_;

    my $res = $cb->(GET '/foobarmatic');
    is $res->code, 404;
};
