#!/usr/bin/env perl

use strict;
use warnings;
use feature 'state';

my $SESSION_NAME = 'saharasync';

my @TMUX_ARGS = (
    [ 'new-session', '-d', '-s', $SESSION_NAME ],
    [ 'split-window', '-h', '-t', $SESSION_NAME . ':0.0' ],
    [ 'split-window', '-v', '-t', $SESSION_NAME . ':0.0' ],
    [ 'split-window', '-v', '-t', $SESSION_NAME . ':0.1' ],
);

sub run_in_tmux {
    my ( $command ) = @_;

    state $window_num = 0;

    my $args = $TMUX_ARGS[$window_num];
    $window_num++;
    system 'tmux', @$args;

    system 'tmux', 'send-keys', '-R', '-t', $SESSION_NAME, $command . "\r";
}

sub attach_tmux {
    system 'tmux', 'attach-session', '-t', $SESSION_NAME;
}

sub select_tmux_pane {
    my ( $pane_no ) = @_;

    system 'tmux', 'select-pane', '-t', $SESSION_NAME . ':0.0';
}

sub pidof {
    my ( $command ) = @_;

    my $output = qx(pidof '$command');
    chomp $output;
    return $output;
}

$ENV{'PATH'} = join(':', '/bin', '/usr/bin');

# XXX option to deploy newest source
# XXX option to set all this shit up

# Pane 0 - hostd
run_in_tmux(q{exec sudo -u saharasync /bin/bash -c '. ~/.perlbrew/etc/bashrc; sahara-hostd -c /var/lib/saharasync/host.yaml'});

sleep(3);

# Pane 1 - clientd
run_in_tmux('perlbrew use saharasync; exec sahara-clientd -c ~/.config/sahara-sync/config.json');

sleep(3);

# Pane 2 - top

my @pids = map { pidof("sahara sync: $_") } qw/client host/;
run_in_tmux('exec top -p ' . join(',', @pids));

# Pane 3 - multitail
run_in_tmux('exec multitail ~/.saharasync/client.log /var/lib/saharasync/hostd.log');

select_tmux_pane(0);

attach_tmux();
