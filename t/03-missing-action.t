use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::Sahara ':methods', tests => 1;

test_host sub {
    my ( $cb ) = @_;

    my $res = $cb->(GET '/foobarmatic');
    is $res->code, 404;
};
