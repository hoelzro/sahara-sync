#!/usr/bin/env perl

use strict;
use warnings;
use feature 'state';

my $SCREEN_NAME = 'saharasync';

sub start_screen {
    system 'screen', '-dmS', $SCREEN_NAME;
}

sub run_in_screen {
    my ( $command ) = @_;

    state $window_num = 0; 

    if($window_num) {
        system 'screen', '-S', $SCREEN_NAME, '-X', 'screen';
    }
    system 'screen', '-S', $SCREEN_NAME, '-p', $window_num, '-X', 'stuff', $command . "\r";
    $window_num++;
}

sub attach_screen {
    system 'screen', '-dr', '-S', $SCREEN_NAME;
}

sub pidof {
    my ( $command ) = @_;

    my $output = qx(pidof '$command');
    chomp $output;
    return $output;
}

$ENV{'PATH'} = join(':', '/bin', '/usr/bin');

# XXX option to deploy newest source

start_screen();

# Screen 0 - hostd
run_in_screen("exec sudo -u saharasync /bin/bash -c '. ~/.perlbrew/etc/bashrc; sahara-hostd -c /var/lib/saharasync/host.yaml'");

sleep(3);

# Screen 1 - clientd
run_in_screen('perlbrew use saharasync; exec sahara-clientd -c ~/.saharasync/client.yaml');

sleep(3);

# Screen 2 - top

my @pids = map { pidof("sahara sync: $_") } qw/client host/;
run_in_screen('exec top -p ' . join(',', @pids));

# Screen 3 - multitail
run_in_screen('exec multitail ~/.saharasync/client.log /var/lib/saharasync/hostd.log');

attach_screen();
