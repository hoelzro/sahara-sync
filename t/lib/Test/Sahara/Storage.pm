package Test::Sahara::Storage;

use strict;
use warnings;
use parent 'Exporter';

use IO::String;
use List::MoreUtils qw(uniq);
use Test::Deep;
use Test::Exception;
use Test::More;

our $VERSION = '0.01';
our @EXPORT = (@Test::More::EXPORT, 'run_store_tests');

sub import {
    my ( $class ) = @_;

    $class->export_to_level(1, @_);
}

sub run_store_tests {
    my ( $store ) = @_;

    subtest 'Testing storage layer' => sub {
        plan tests => 53;

        my $info;
        my $blob;
        my $exists;

        $info = $store->load_user_info('test');
        ok $info;
        is ref($info), 'HASH';
        is $info->{'username'}, 'test';
        is $info->{'password'}, 'abc123';

        $info = $store->load_user_info('test3');
        ok ! defined($info);

        $blob = $store->fetch_blob('test', 'file.txt');
        ok ! defined($blob);
        $blob = $store->fetch_blob('test', 'file2.txt');
        ok ! defined($blob);

        dies_ok {
            $blob = $store->fetch_blob('test3', 'file.txt');
        };

        $exists = $store->store_blob('test', 'file.txt', IO::String->new('Hello, World!'));
        ok ! $exists;

        dies_ok {
            $blob = $store->fetch_blob('test3', 'file.txt');
        };

        $blob = $store->fetch_blob('test', 'file.txt');
        ok defined($blob);
        isa_ok $blob, 'IO::Handle';
        $blob = do { local $/; <$blob> };
        is $blob, 'Hello, World!';
        $blob = $store->fetch_blob('test', 'file2.txt');
        ok ! defined($blob);
        $blob = $store->fetch_blob('test2', 'file.txt');
        ok ! defined($blob);

        $exists = $store->store_blob('test', 'file.txt');
        ok $exists;
        $blob = $store->fetch_blob('test', 'file.txt');
        ok ! defined($blob);

        $exists = $store->store_blob('test', 'file.txt', IO::String->new('Hello, World!'));
        ok ! $exists;
        $exists = $store->store_blob('test', 'file.txt', IO::String->new('Hello, World!'));
        ok $exists;

        $exists = $store->store_blob('test2', 'file.txt', IO::String->new('Hi there'));
        ok ! $exists;
        $blob = $store->fetch_blob('test', 'file.txt');
        ok $blob;
        isa_ok $blob, 'IO::Handle';
        $blob = do { local $/; <$blob> };
        is $blob, 'Hello, World!';
        $blob = $store->fetch_blob('test2', 'file.txt');
        ok $blob;
        isa_ok $blob, 'IO::Handle';
        $blob = do { local $/; <$blob> };
        is $blob, 'Hi there';

        dies_ok {
            $store->store_blob('test', 'file.txt', 'Text');
        };
        dies_ok {
            $store->store_blob('test', 'file2.txt', 'Text');
        };

        $exists = $store->store_blob('test', 'file.txt');
        ok $exists;
        $exists = $store->store_blob('test', 'file.txt');
        ok ! $exists;

        dies_ok {
            $store->store_blob('test3', 'file.txt', 'Text');
        };
        dies_ok {
            $store->store_blob('test3', 'file.txt', IO::String->new('Text'));
        };
        dies_ok {
            $store->store_blob('test3', 'file.txt');
        };

        $store->store_blob('test', 'file2.txt', IO::String->new('Text'));

        my @all_test_changes = uniq $store->fetch_changed_blobs('test', 0);

        cmp_bag(\@all_test_changes, ['file.txt', 'file2.txt']);

        my @all_test2_changes = uniq $store->fetch_changed_blobs('test2', 0);

        cmp_bag(\@all_test2_changes, ['file.txt']);

        sleep 1;
        my $now = time;
        sleep 2;
        $store->store_blob('test', 'file3.txt', IO::String->new('More text'));

        my @test_changes  = uniq $store->fetch_changed_blobs('test', $now);
        my @test2_changes = uniq $store->fetch_changed_blobs('test2', $now);

        cmp_bag(\@test_changes, ['file3.txt']);
        cmp_bag(\@test2_changes, []);

        @test_changes  = uniq $store->fetch_changed_blobs('test', $now + 60);
        @test2_changes = uniq $store->fetch_changed_blobs('test2', $now + 60);

        cmp_bag(\@test_changes, []);
        cmp_bag(\@test2_changes, []);

        dies_ok {
            $store->fetch_changed_blobs('test3', 0);
        };
        dies_ok {
            $store->fetch_changed_blobs('test3', $now);
        };
        dies_ok {
            $store->fetch_changed_blobs('test3', $now + 60);
        };

        sleep 1;
        $now = time;
        $store->store_blob('test', 'file4.txt', IO::String->new('Even more text'));
        $store->store_blob('test', 'file4.txt');
        sleep 2;

        @test_changes  = uniq $store->fetch_changed_blobs('test', $now);
        cmp_bag(\@test_changes, ['file4.txt']);

        $exists = $store->store_blob('test', 'dir/file.txt', IO::String->new('hey'));
        ok !$exists;
        $blob = $store->fetch_blob('test', 'dir/file.txt');
        ok $blob;
        isa_ok $blob, 'IO::Handle';
        $blob = do { local $/; <$blob> };
        is $blob, 'hey';

        my $ok = $store->create_user('test', 'abc123');
        ok !$ok;
        $ok = $store->create_user('test3', 'abc123');
        ok $ok;

        $ok = $store->remove_user('test4');
        ok !$ok;
        $ok = $store->remove_user('test3');
        ok $ok;
        $ok = $store->remove_user('test3');
        ok !$ok;

        $store->create_user('test3', 'abc123');
        $store->store_blob('test3', 'file.txt', IO::String->new('my text'));
        $store->remove_user('test3');
        $store->create_user('test3', 'abc123');
        $blob = $store->fetch_blob('test3', 'file.txt');
        ok !$blob;
    };
}

1;

__END__

=head1 NAME

Test::Sahara::Storage

=head1 VERSION

0.01

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=head1 AUTHOR

Rob Hoelz, C<< rob at hoelz.ro >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-SaharaSync at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=SaharaSync>. I will
be notified, and then you'll automatically be notified of progress on your bug as I make changes.

=head1 COPYRIGHT & LICENSE

Copyright 2011 Rob Hoelz.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

=cut
