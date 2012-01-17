package Test::Sahara::Host;

use strict;
use warnings;
use parent 'Test::Sahara::ChildProcess';

sub new {
    my ( $class ) = @_;

    return Test::Sahara::ChildProcess::new($class, sub {
        my ( $port ) = @_;

        $ENV{'_HOSTD_PORT'} = $port;

        exec $^X, 't/run-test-app';
    });
}

1;
