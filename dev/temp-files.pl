#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use File::Slurp qw(read_dir);

my @test_methods = map { chomp; $_ } <DATA>;

$ENV{'TMPDIR'} = '/tmp/sahara';

foreach my $method (@test_methods) {
    $ENV{'TEST_METHOD'} = $method;

    system 'prove t/client/sync-streaming.t >/dev/null 2>&1';
    my @temp_files = read_dir('/tmp/sahara');
    system 'rm -rf /tmp/sahara/*';
    say $method if @temp_files;
}

__DATA__
test_create_conflict
test_create_file
test_delete_file
test_delete_update_conflict
test_offline_update
test_preexisting_files
test_revision_persistence
test_update_conflict
test_update_delete_conflict
test_update_file
test_update_on_nonorigin
