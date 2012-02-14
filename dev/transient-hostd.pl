#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use File::Path qw(make_path remove_tree);
use YAML qw(DumpFile);

my $host              = '127.0.0.1';
my $disable_streaming = 1;

GetOptions(
    'host=s'            => \$host,
    'diasble-streaming' => \$disable_streaming,
);

mkdir 'logs';
make_path('transient-data/host/files');

DumpFile('transient-data/host/config.yaml', {
    server => {
        host              => $host,
        disable_streaming => $disable_streaming,
    },
    storage => {
        type         => 'DBIWithFS',
        dsn          => 'dbi:SQLite:dbname=transient-data/host/data.db',
        storage_path => 'transient-data/host/files',
    },
    log => [{
        type      => 'Screen',
        newline   => 1,
        stderr    => 0,
        min_level => 'debug',
    }, {
        type      => 'File',
        mandatory => 1,
        newline   => 1,
        mode      => 'write',
        filename  => 'logs/hostd.log',
        min_level => 'debug',
    }]
});

system('sqlite3', '-init', 'schema.sqlite', 'transient-data/host/data.db',
    q{INSERT INTO users (username, password) VALUES ('rob', '12345')});

$ENV{'PERL5LIB'} .= ':lib/';

system('bin/sahara-hostd', '-c', 'transient-data/host/config.yaml');

remove_tree 'transient-data/host';
