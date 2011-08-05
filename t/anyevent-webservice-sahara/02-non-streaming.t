use strict;
use warnings;
use parent 'AnyEvent::WebService::Sahara::Test';

sub create_fresh_app {
    return Test::Sahara->create_fresh_app(
        server => {
            disable_streaming => 1,
        },
    );
}

Test::Class->runtests;
