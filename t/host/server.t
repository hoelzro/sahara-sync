use strict;
use warnings;

use Test::More;
use Plack::Test::Suite;

Plack::Test::Suite->run_server_tests('SaharaSync');
done_testing;
