#!/usr/bin/env perl

use strict;
use warnings;

use File::Path qw(make_path remove_tree);
use YAML qw(DumpFile);

my ( $upstream ) = @ARGV;

$upstream = 'http://localhost:5982' unless defined $upstream;

mkdir 'logs';
make_path('transient-data/client/files');

DumpFile('transient-data/client/config.yaml', {
    upstream => $upstream,
    username => 'rob',
    password => '12345',
    sync_dir => 'transient-data/client/files',
    log      => [{
        type      => 'Screen',
        newline   => 1,
        stderr    => 0,
        min_level => 'debug',
    }, {
        type      => 'File',
        mandatory => 1,
        newline   => 1,
        mode      => 'write',
        filename  => 'logs/client.log',
        min_level => 'debug',
    }],
});

$ENV{'PERL5LIB'} .= ':lib/';

system('bin/sahara-clientd', '-c', 'transient-data/client/config.yaml');

remove_tree 'transient-data/client';
