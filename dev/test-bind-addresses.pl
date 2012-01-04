#!/usr/bin/env perl

use strict;
use warnings;
use autodie qw(fork pipe);
use feature 'say';

use Regexp::Common qw(net);

my $BIND_ADDR = qr/inet_addr\("(?<address>$RE{net}{IPv4})"\)/;

foreach my $test (@ARGV) {
    my $command = "strace -f -e bind perl -Ilib -It/lib $test";

    my ( $read, $write );
    pipe $read, $write;
    my $pid = fork;

    my %addresses;

    if($pid) {
        close $write;
        while(<$read>) {
            chomp;
            if(/$BIND_ADDR/) {
                $addresses{ $+{'address'} } = 1;
            }
        }
        waitpid $pid, 0;
    } else {
        close $read;
        close STDOUT;
        open STDERR, '>&', $write;
        exec $command;
    }

    delete $addresses{'127.0.0.1'};

    say $test;
    if(keys %addresses) {
        say "  $_" foreach sort keys %addresses;
    }
}
