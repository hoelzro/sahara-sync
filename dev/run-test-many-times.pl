#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use TAP::Harness;

my $harness = TAP::Harness->new({
    lib       => ['lib', 't/lib'],
    verbosity => -3,
    failures  => 0,
});

my @failures;

local $SIG{USR1} = sub {
    say;
};

for(1..100) {
    my $agg = $harness->runtests('t/anyevent-webservice-sahara/01-streaming.t');
    $failures[$agg->failed]++;
    say "$_ tests run" unless $_ % 10;
}

printf "%3d passed\n", shift(@failures) // 0;
printf "%3d with 1 failure\n", shift(@failures) // 0;
my $failures = 2;
while(@failures) {
    printf "%3d with $failures failures\n", shift(@failures) // 0;
    $failures++;
}
