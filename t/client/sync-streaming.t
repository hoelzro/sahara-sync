use strict;
use warnings;
use parent 'SaharaSync::Clientd::SyncTest';

use Test::More;

my $sd = SaharaSync::Clientd::SyncDir->create_syncdir(
    root => File::Temp->newdir->dirname,
);

if(defined $sd) {
    __PACKAGE__->runtests;
} else {
    plan skip_all => 'No sync dir implemention exists for this OS';
}
