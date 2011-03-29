#!/usr/bin/env perl

use strict;
use warnings;

use File::Find;
use File::Spec;
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../lib";

my @modules;

find(sub {
    return unless /\.pm/;
    my $name = $File::Find::name;
    $name =~ s/^\Q$FindBin::Bin\/..\/lib\/\E//;
    $name =~ s/\.pm$//;
    $name =~ s!/!::!g;
    push @modules, $name;
}, "$FindBin::Bin/../lib");

plan tests => scalar(@modules);
use_ok($_) foreach @modules;
