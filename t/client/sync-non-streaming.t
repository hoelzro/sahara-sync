use strict;
use warnings;
use parent 'SaharaSync::Clientd::SyncTest';

use Test::More;

sub create_fresh_app {
    return Test::Sahara->create_fresh_app(
        server => {
            disable_streaming => 1,
        },
    );
}

my $sd = SaharaSync::Clientd::SyncDir->create_syncdir(
    root => File::Temp->newdir->dirname,
);

if(defined $sd) {
    __PACKAGE__->runtests;
} else {
    plan skip_all => 'No sync dir implemention exists for this OS';
}
