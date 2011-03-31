use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use HTTP::Request::Common;
use Plack::Test;
use Test::More tests => 1;

use SaharaSync::Hostd;

my $app = SaharaSync::Hostd->to_app;

test_psgi $app, sub {
    my ( $cb ) = @_;

    my $res = $cb->(GET '/foobarmatic');
    is $res->code, 404;
};
