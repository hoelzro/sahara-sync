use strict;
use warnings;
use parent 'SaharaSync::Clientd::SyncTest';

sub create_fresh_app {
    return Test::Sahara->create_fresh_app(
        server => {
            disable_streaming => 1,
        },
    );
}

__PACKAGE__->runtests;
