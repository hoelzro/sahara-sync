#!/usr/bin/env perl

package My::Parser;

use strict;
use warnings;
use parent 'TAP::Parser';

our @comments;

sub new {
    my ( $class, $opts ) = @_;

    my $callbacks = $opts->{'callbacks'};
    unless($callbacks) {
        $opts->{'callbacks'} = $callbacks = {};
    }
    my $comment_cb = $callbacks->{'comment'} || sub {};
    $callbacks->{'comment'} = sub {
        my ( $comment ) = @_;
        push @comments, $comment->as_string =~ s/^#\s*//r;
        goto &$comment_cb;
    };

    my $new = TAP::Parser->can('new');
    return $class->$new($opts);
}

package main;

use strict;
use warnings;
use lib 'lib';
use lib 't/lib';
use feature 'say';

die "usage: $0 [test file]\n" unless @ARGV;
my ( $test ) = @ARGV;

use TAP::Harness;

delete $ENV{'TEST_METHOD'};

my $tap = TAP::Harness->new({
    lib       => [ 'lib', 't/lib' ],
    verbosity => -3,
    switches  => [
        '-MTest::Class',
        '-MTest::More',
        '-e', '*{"Test::Class::runtests"} = sub { diag($_) foreach __PACKAGE__->_get_methods("test"); plan tests => 1; pass; };',
        '-e', "do '$test' || die \$\@;",
    ],
    parser_class => 'My::Parser',
    comments  => 0,
    merge     => 1,
});

$tap->runtests($test);

my @methods = @My::Parser::comments;

say foreach @methods;
