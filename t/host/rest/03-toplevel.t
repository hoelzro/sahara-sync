use strict;
use warnings;

use Test::Sahara ':methods', tests => 3;

test_host sub {
    my ( $cb ) = @_;

    my $res = $cb->(HEAD '/');
    is $res->code, 200;
    ok defined($res->header('X-Sahara-Capabilities'));
    is $res->header('X-Sahara-Version'), $SaharaSync::Hostd::VERSION;
};
