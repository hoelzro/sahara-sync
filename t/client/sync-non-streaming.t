use strict;
use warnings;
use parent 'SaharaSync::Clientd::SyncTest';

use File::Temp;
use Test::More;
use SaharaSync::Clientd::BlobStore;

sub hostd_options {
    return (
        disable_streaming => 1,
    );
}

my $tempdir = File::Temp->newdir;
my $store = SaharaSync::Clientd::BlobStore->create(
    root => $tempdir->dirname,
);

if(defined $store) {
    __PACKAGE__->runtests;
} else {
    plan skip_all => 'No local blob storage implemention exists for this OS';
}
