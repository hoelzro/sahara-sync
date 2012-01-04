#!/usr/bin/env perl

use strict;
use warnings;
use autodie qw(fork);

use AnyEvent;

use Smart::Comments;

my $TOTAL   = 10_000;
my $TIMEOUT = 3;
my $OUTPUT = 'test.out';

my $num_normal   = 0;
my $num_abnormal = 0;
my $num_timeout  = 0;

for my $i ( 1 .. $TOTAL ) { ### Running Tests [===|             ] % done.
    my $pid = fork();

    unless($pid) {
        close STDOUT;
        close STDERR;

        open STDOUT, '>', $OUTPUT;
        open STDERR, '>&', \*STDOUT;

        exec 'perl', '-Ilib', '-It/lib', 't/test-libs/proxy-test.t';
    }

    my $status;

    do {
        my $cond = AnyEvent->condvar;

        my $timer = AnyEvent->timer(
            after => $TIMEOUT,
            cb    => sub {
                $cond->send;
            },
        );

        my $child = AnyEvent->child(
            pid => $pid,
            cb  => sub {
                ( undef, $status ) = @_;

                $cond->send;
            },
        );

        $cond->recv;
    };

    if(defined $status) {
        if($status) {
            $num_abnormal++;
        } else {
            $num_normal++;
        }
    } else {
        # timeout
        kill TERM => $pid;
        waitpid $pid, 0;

        $num_timeout++;
    }
}

printf "  # Normal exit: %d\n", $num_normal;
printf "# Abnormal exit: %d\n", $num_abnormal;
printf "      # Timeout: %d\n", $num_timeout;
