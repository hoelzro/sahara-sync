#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use File::Slurp qw(read_dir);

my @test_methods = map { chomp; $_ } qx(perl dev/print-test-class-methods.pl t/client/sync-streaming.t);

$ENV{'TMPDIR'} = '/tmp/sahara';

foreach my $method (@test_methods) {
    $ENV{'TEST_METHOD'} = $method;

    mkdir '/tmp/sahara';
    system 'prove t/client/sync-streaming.t >/dev/null 2>&1';
    my @temp_files = read_dir('/tmp/sahara');
    system 'rm -rf /tmp/sahara/*';
    say $method if @temp_files;
}
