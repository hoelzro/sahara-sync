use strict;
use warnings;
use parent 'SaharaSync::Clientd::SyncTest';

use File::Temp;
use Test::More;
use SaharaSync::Clientd::SyncDir;

sub hostd_options {
    return (
        disable_streaming => 1,
    );
}

my $tempdir = File::Temp->newdir;
my $sd = SaharaSync::Clientd::SyncDir->create_syncdir(
    root => $tempdir->dirname,
);

if(defined $sd) {
    __PACKAGE__->runtests;
} else {
    plan skip_all => 'No sync dir implemention exists for this OS';
}
