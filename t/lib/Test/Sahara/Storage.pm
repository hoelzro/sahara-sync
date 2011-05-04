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
    my ( $store, $name ) = @_;

    if($name) {
        $name = "Testing storage layer ($name)";
    } else {
        $name = "Testing storage layer";
    }

    subtest $name => sub {
        plan tests => 53;

        my $info;
        my $blob;
        my $exists;

        $info = $store->load_user_info('test');
        ok $info, "Verify that test user exists and yields data";
        is ref($info), 'HASH', "Verify that load_user_info returns a hash reference";
        is $info->{'username'}, 'test', "Verify that load_user_info includes a username field";
        is $info->{'password'}, 'abc123', "Verify that load_user_info includes a password field";

        $info = $store->load_user_info('test3');
        ok ! defined($info), "Verify that load_user_info returns undef for a non-existent user";

        $blob = $store->fetch_blob('test', 'file.txt');
        ok ! defined($blob), "fetch_blob should return undef for a non-existent blob";
        $blob = $store->fetch_blob('test', 'file2.txt');
        ok ! defined($blob), "fetch_blob should return undef for a non-existent blob";

        dies_ok {
            $blob = $store->fetch_blob('test3', 'file.txt');
        } "fetch_blob should die for a non-existent user";

        $exists = $store->store_blob('test', 'file.txt', IO::String->new('Hello, World!'));
        ok ! $exists, "Storing a new blob should return a falsy value";

        dies_ok {
            $blob = $store->fetch_blob('test3', 'file.txt');
        } "fetch_blob should die for a non-existent user";

        $blob = $store->fetch_blob('test', 'file.txt');
        ok defined($blob), "Fetching an existent blob should return a truthy value";
        isa_ok $blob, 'IO::Handle', "Fetching an existent blob should return an IO::Handle";
        $blob = do { local $/; <$blob> };
        is $blob, 'Hello, World!', "The contents of the returned handle should match the last store operation";
        $blob = $store->fetch_blob('test', 'file2.txt');
        ok ! defined($blob), "Fetching a non-existent blob should return undef";
        $blob = $store->fetch_blob('test2', 'file.txt');
        ok ! defined($blob), "Fetching a non-existent blob should return undef";

        $exists = $store->store_blob('test', 'file.txt');
        ok $exists, "Deleting an existent blob should return a truthy value";
        $blob = $store->fetch_blob('test', 'file.txt');
        ok ! defined($blob), "Storing undef as a blob's contents should delete the blob";

        $exists = $store->store_blob('test', 'file.txt', IO::String->new('Hello, World!'));
        ok ! $exists, "Storing a non-existent (but once existent) blob should return a falsy value";
        $exists = $store->store_blob('test', 'file.txt', IO::String->new('Hello, World!'));
        ok $exists, "Storing an existent blob should return a truthy value";

        $exists = $store->store_blob('test2', 'file.txt', IO::String->new('Hi there'));
        ok ! $exists, "Storing a non-existent blob should return a falsy value";
        $blob = $store->fetch_blob('test', 'file.txt');
        ok $blob, "Fetching an existent blob should return a truthy value";
        isa_ok $blob, 'IO::Handle', "Fetching an existent blob should return an IO::Handle";
        $blob = do { local $/; <$blob> };
        is $blob, 'Hello, World!', "Two separate users using the same blob name should not affect one another";
        $blob = $store->fetch_blob('test2', 'file.txt');
        ok $blob, "Fetching an existent blob should return a truthy value";
        isa_ok $blob, 'IO::Handle', "Fetching an existent blob should return an IO::Handle";
        $blob = do { local $/; <$blob> };
        is $blob, 'Hi there', "The contents of the returned handle should match the last store operation";

        dies_ok {
            $store->store_blob('test', 'file.txt', 'Text');
        } "Storing something other than an IO::Handle or undef should die";
        dies_ok {
            $store->store_blob('test', 'file2.txt', 'Text');
        } "Storing something other than an IO::Handle or undef should die";

        $exists = $store->store_blob('test', 'file.txt');
        ok $exists, "Deleting an existent blob should return a truthy value";
        $exists = $store->store_blob('test', 'file.txt');
        ok ! $exists, "Deleting an non-existent blob should return a falsy value";

        dies_ok {
            $store->store_blob('test3', 'file.txt', 'Text');
        } "store_blob should die for a non-existent user";
        dies_ok {
            $store->store_blob('test3', 'file.txt', IO::String->new('Text'));
        } "store_blob should die for a non-existent user";
        dies_ok {
            $store->store_blob('test3', 'file.txt');
        } "store_blob should die for a non-existent user";

        $store->store_blob('test', 'file2.txt', IO::String->new('Text'));

        my @all_test_changes = uniq $store->fetch_changed_blobs('test', 0);

        cmp_bag(\@all_test_changes, ['file.txt', 'file2.txt'], "The list of all changed blobs should include all blobs changed for the given user");

        my @all_test2_changes = uniq $store->fetch_changed_blobs('test2', 0);

        cmp_bag(\@all_test2_changes, ['file.txt'], "The list of all changed blobs should include all blobs changed for the given user");

        sleep 1;
        my $now = time;
        sleep 2;
        $store->store_blob('test', 'file3.txt', IO::String->new('More text'));

        my @test_changes  = uniq $store->fetch_changed_blobs('test', $now);
        my @test2_changes = uniq $store->fetch_changed_blobs('test2', $now);

        cmp_bag(\@test_changes, ['file3.txt'], "The list of changed blobs since a timestamp should only include blobs changed since that timestamp");
        cmp_bag(\@test2_changes, [], "The list of changed blobs since a timestamp should only include blobs changed since that timestamp");

        @test_changes  = uniq $store->fetch_changed_blobs('test', $now + 60);
        @test2_changes = uniq $store->fetch_changed_blobs('test2', $now + 60);

        cmp_bag(\@test_changes, [], "The list of changed blobs since a future timestamp should be empty");
        cmp_bag(\@test2_changes, [], "The list of changed blobs since a future timestamp should be empty");

        dies_ok {
            $store->fetch_changed_blobs('test3', 0);
        } "Fetching changed blobs for a non-existent user should die";
        dies_ok {
            $store->fetch_changed_blobs('test3', $now);
        } "Fetching changed blobs for a non-existent user should die";
        dies_ok {
            $store->fetch_changed_blobs('test3', $now + 60);
        } "Fetching changed blobs for a non-existent user should die";

        sleep 1;
        $now = time;
        $store->store_blob('test', 'file4.txt', IO::String->new('Even more text'));
        $store->store_blob('test', 'file4.txt');
        sleep 2;

        @test_changes  = uniq $store->fetch_changed_blobs('test', $now);
        cmp_bag(\@test_changes, ['file4.txt'], "A file that has been created and deleted should still appear in the change list");

        $exists = $store->store_blob('test', 'dir/file.txt', IO::String->new('hey'));
        ok !$exists, "Creating a blob with a slash in its name should return a falsy value";
        $blob = $store->fetch_blob('test', 'dir/file.txt');
        ok $blob, "Fetching an existent blob with a slash in its name should return an IO::Handle";
        isa_ok $blob, 'IO::Handle';
        $blob = do { local $/; <$blob> };
        is $blob, 'hey', "The returned IO::Handle should match the contents of the previous store operation";

        my $ok = $store->create_user('test', 'abc123');
        ok !$ok, "Trying to create an existent user should return a falsy value";
        $ok = $store->create_user('test3', 'abc123');
        ok $ok, "Trying to create a non-existent user should return a truthy value";

        $ok = $store->remove_user('test4');
        ok !$ok, "Trying to remove a non-existent user should return a falsy value";
        $ok = $store->remove_user('test3');
        ok $ok, "Trying to remove an existent user should return a truthy value";
        $ok = $store->remove_user('test3');
        ok !$ok, "Trying to remove a non-existent user that once existed should return a falsy value";

        $store->create_user('test3', 'abc123');
        $store->store_blob('test3', 'file.txt', IO::String->new('my text'));
        $store->remove_user('test3');
        $store->create_user('test3', 'abc123');
        $blob = $store->fetch_blob('test3', 'file.txt');
        ok !$blob, "Fetching a blob which was created by a user that has since been deleted and recreated should return undef";
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
