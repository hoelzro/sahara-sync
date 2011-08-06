use strict;
use warnings;

use Test::Sahara ':methods';

use JSON qw(decode_json);

sub permutations {
    my ( $value, @rest ) = @_;

    if(@rest) {
        my @perms = permutations(@rest);
        my @retval;

        foreach my $perm (@perms) {
            for(my $i = 0; $i <= @$perm; $i++) {
                my @copy = @$perm;
                splice @copy, $i, 0, $value;
                push @retval, \@copy;
            }
        }
        return @retval;
    } else {
        return ( [ $value ] );
    }
}

sub factorial {
    my ( $n ) = @_;

    my $fact = 1;

    $fact *= $n-- while $n;

    return $fact;
}

my @names = (
    'file.txt',
    'file1.txt',
    'file2.txt',
);

plan tests => factorial(scalar @names);

foreach my $perm (permutations @names) {
    test_host sub {
        my ( $cb ) = @_;

        my @revisions;

        foreach my $blob (@$perm) {
            my $res = $cb->(PUT_AUTHD "/blobs/$blob", Content => "In $blob!");
            push @revisions, $res->header('ETag');
        }

        my $res     = $cb->(GET_AUTHD '/changes.json', Connection => 'close');
        my $changes = decode_json($res->content);
        my @expected = map {
            {
                name     => $perm->[$_],
                revision => $revisions[$_],
            }
        } (0..$#revisions);

        is_deeply($changes, \@expected);
    };
}
