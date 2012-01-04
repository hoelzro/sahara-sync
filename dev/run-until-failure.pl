#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

delete $ENV{'TEST_METHOD'};
$ENV{'TEST_METHOD'}        = 'test_update_file';
$ENV{'TEST_HOSTD_DEBUG'}   = 1;
$ENV{'TEST_CLIENTD_DEBUG'} = 1;

my $TOTAL  = 500;
my $output = 'test.out';
my $cmd    = 'prove t/client/sync-streaming.t';
my $i;

$SIG{USR1} = sub {
    say $i;
};

for($i = 1; $i <= $TOTAL; $i++) {
    system "$cmd >$output 2>&1";
    if($?) {
        say $i;
        system 'cat', $output;
        exit(1);
    }
}

say "No failures after $TOTAL iterations";
exit(0);
