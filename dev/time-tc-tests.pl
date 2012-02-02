#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use TAP::Harness;

die "usage: $0 [test file]\n" unless @ARGV;
my ( $test ) = @ARGV;

my $tap = TAP::Harness->new({
    lib       => [ 'lib', 't/lib', 'dev/lib' ],
    verbosity => -3,
    switches  => [
        '-d:TestClassTiming',
    ],
});

$tap->runtests($test);
