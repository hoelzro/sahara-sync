package Test::Sahara::Host;

use strict;
use warnings;
use parent 'Test::Sahara::ChildProcess';

sub new {
    my ( $class, %options ) = @_;

    return Test::Sahara::ChildProcess::new($class, sub {
        my ( $port ) = @_;

        $ENV{'_HOSTD_PORT'} = $port;
        if($options{'disable_streaming'}) {
            $ENV{'_HOSTD_DISABLE_STREAMING'} = 1;
        }

        exec $^X, 't/run-test-app';
    });
}

1;
