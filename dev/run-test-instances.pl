#!/usr/bin/env perl

use strict;
use warnings;
use autodie qw(fork);

# Thie script loads up a temporary instance of a hostd and two clientds, and
# then places you in a shell so you can do exploratory work with a running
# instance of Sahara Sync without having to configure the daemons yourself.

use Cwd qw(getcwd);
use DBI;
use Guard;
use File::Spec;
use File::Temp;
use YAML qw(DumpFile);

my %BASE_HOST_CONFIG = (
    server => {
        host              => '127.0.0.1',
        disable_streaming => 1,
    },
);

my %BASE_CLIENT_CONFIG = (
    upstream => 'http://localhost:5982',
    username => 'rob',
    password => '12345',
);

my @child_pids;

sub run_in_terminal {
    my ( $command, @args ) = @_;

    my %options;

    if(ref($args[-1]) eq 'HASH') {
        %options = %{ pop(@args) };
    }

    if(my $pid = fork) {
        push @child_pids, $pid;
        sleep 1;
    } else {
        my @command_line = ( 'xterm' );

        if(my $title = $options{'title'}) {
            push @command_line, '-title', $title;
        }
        push @command_line, '-e', $command, @args;
        exec @command_line;
    }
}

sub wait_for_children {
    while(@child_pids) {
        my $pid = waitpid -1, 0;
        @child_pids = grep { $_ != $pid } @child_pids;
    }
}

my $original_wd = getcwd;
my $root        = File::Temp->newdir;
my $hostd       = File::Spec->catfile($original_wd, 'bin', 'sahara-hostd');
my $clientd     = File::Spec->catfile($original_wd, 'bin', 'sahara-clientd');
my $schema      = File::Spec->catfile($original_wd, 'schema.sqlite');

mkdir 'logs';

$ENV{'PERL5LIB'} .= ':' . File::Spec->catfile($original_wd, 'lib');

do {
    my $guard = guard {
        chdir $original_wd;
    };

    chdir $root->dirname;

    mkdir 'host-files';
    mkdir 'client1-files';
    mkdir 'client2-files';

    DumpFile('host.yaml', {
        %BASE_HOST_CONFIG,
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
            filename  => File::Spec->catfile($original_wd, 'logs', 'hostd.log'),
            min_level => 'debug',
        }],
        storage => {
            type         => 'DBIWithFS',
            dsn          => 'dbi:SQLite:dbname=' . File::Spec->catfile($root->dirname, 'host.db'),
            storage_path => File::Spec->catfile($root->dirname, 'host-files'),
        },
    });

    DumpFile('client1.yaml', {
        %BASE_CLIENT_CONFIG,
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
            filename  => File::Spec->catfile($original_wd, 'logs', 'client1.log'),
            min_level => 'debug',
        }],
        sync_dir => File::Spec->catfile($root->dirname, 'client1-files'),
    });

    DumpFile('client2.yaml', {
        %BASE_CLIENT_CONFIG,
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
            filename  => File::Spec->catfile($original_wd, 'logs', 'client2.log'),
            min_level => 'debug',
        }],
        sync_dir => File::Spec->catfile($root->dirname, 'client2-files'),
    });

    my $hostd_config    = File::Spec->catfile($root->dirname, 'host.yaml');
    my $clientd1_config = File::Spec->catfile($root->dirname, 'client1.yaml');
    my $clientd2_config = File::Spec->catfile($root->dirname, 'client2.yaml');

    system('sqlite3', '-init', $schema, 'host.db', '.quit');
    system('sqlite3', 'host.db', q{INSERT INTO users (username, password) VALUES ('rob', '12345')});

    run_in_terminal($hostd, '-c', $hostd_config, {
        title => 'hostd',
    });
    run_in_terminal($clientd, '-c', $clientd1_config, {
        title => 'clientd 1',
    });
    run_in_terminal($clientd, '-c', $clientd2_config, {
        title => 'clientd 2',
    });
    run_in_terminal('bash');

    wait_for_children;
};
