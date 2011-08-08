use strict;
use warnings;

use Test::More tests => 3;
use Test::Sahara ':methods';

test_host sub {
    my ( $cb ) = @_;

    my $res = $cb->(HEAD '/');
    is $res->code, 200, "Calling HEAD on / should result in a 200";
    ok defined($res->header('X-Sahara-Capabilities')), "HEAD / should return the X-Sahara-Capabilities header";
    is $res->header('X-Sahara-Version'), $SaharaSync::Hostd::VERSION, "HEAD / should return the server version in the X-Sahara-Version header";
};
