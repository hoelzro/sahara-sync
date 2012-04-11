use strict;
use warnings;
use parent 'SaharaSync::Clientd::BlobStoreTest';

use File::Temp;
use SaharaSync::Clientd::BlobStore;
use Test::More;

my $tempdir = File::Temp->newdir;
my $sd      = SaharaSync::Clientd::BlobStore->create(
    root => $tempdir->dirname,
);

if(defined $sd) {
    __PACKAGE__->runtests;
} else {
    plan skip_all => 'No sync dir implemention exists for this OS';
}

