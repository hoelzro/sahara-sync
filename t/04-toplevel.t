use strict;
use warnings;
use FindBin;

use lib "$FindBin::Bin/../lib";

use HTTP::Request::Common;
use Plack::Test;
use Test::More tests => 3;

use SaharaSync::Hostd;

my $app = SaharaSync::Hostd->to_app;

test_psgi $app, sub {
    my ( $cb ) = @_;

    my $res = $cb->(HEAD '/');
    is $res->code, 200;
    ok defined($res->header('X-Sahara-Capabilities'));
    is $res->header('X-Sahara-Version'), $SaharaSync::Hostd::VERSION;
};
