#!/usr/bin/env perl

# This script organizes log entries into groups based on their times
# (everything within three seconds is considered a group) and 
# applies colors to each group, so it's easy to see which log events
# are "probably" related

use strict;
use warnings;
use feature 'say';

my $LOG_REGEX   = qr{
\A
\[ ( [^]]+ ) \] # sequence of non-] characters enclosed in [ ]
(.*)
\z}x;

my $FORMAT      = '%F %T';
my $WINDOW_SIZE = 3;

use DateTime;
use DateTime::Format::Strptime qw(strftime strptime);
use Term::ANSIColor qw(colored);

my @colors = (
    [ 'white on_red' ],
    [ 'white on_yellow' ],
    [ 'white on_green' ],
);

my $current_color_index = -1;
my $current_timestamp   = 0;

while(<>) {
    chomp;

    if(my ( $time, $message) = /$LOG_REGEX/) {
        $time = strptime($FORMAT, $time);

        my $timestamp = $time->epoch;
        if($timestamp > $current_timestamp + $WINDOW_SIZE) {
            $current_color_index++;
            $current_color_index %= @colors;
            $current_timestamp    = $timestamp;
        }
        my $color = $colors[$current_color_index];

        $message      = '[' . strftime($FORMAT, $time) . '] ' . $message;
        say colored($color, $message);
    }
}
