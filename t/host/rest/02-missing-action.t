use strict;
use warnings;

use Test::Sahara ':methods', tests => 1;

test_host sub {
    my ( $cb ) = @_;

    my $res = $cb->(GET '/foobarmatic');
    is $res->code, 404, "Non-existent actions should result in a 404";
};
