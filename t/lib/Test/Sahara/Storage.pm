package Test::Sahara::Storage;

use strict;
use warnings;
use parent 'Exporter';

use IO::String;
use File::Slurp qw(read_file);
use File::Spec;
use File::Temp qw(tempfile);
use List::MoreUtils qw(uniq);
use Symbol qw(gensym);
use Test::Deep;
use Test::Exception;
use Test::More;

our $VERSION = '0.01';
our @EXPORT = (@Test::More::EXPORT, 'run_store_tests');

my $BAD_REVISION = '0' x 64;

sub import {
    my ( $class ) = @_;

    $class->export_to_level(1, @_);
}

sub slurp_handle {
    my ( $h ) = @_;

    my $contents = '';
    while(defined(my $line = $h->getline)) {
        $contents .= $line;
    }
    return $contents;
}

sub run_store_tests {
    my ( $store, $name ) = @_;

    if($name) {
        $name = "Testing storage layer ($name)";
    } else {
        $name = "Testing storage layer";
    }

    subtest $name => sub {
        plan tests => 97;

        my $info;
        my $blob;
        my $revision;
        my $revision2;
        my $last_revision;
        my @changes;
        
        ######################## Test load_user_info #########################
        $info = $store->load_user_info('test');
        ok $info, "Verify that test user exists and yields data";
        is ref($info), 'HASH', "Verify that load_user_info returns a hash reference";
        is $info->{'username'}, 'test', "Verify that load_user_info includes a username field";
        is $info->{'password'}, 'abc123', "Verify that load_user_info includes a password field";

        $info = $store->load_user_info('test3');
        ok ! defined($info), "Verify that load_user_info returns undef for a non-existent user";

        ########################## Test fetch_blob ###########################
        throws_ok {
            $blob = $store->fetch_blob('test', 'file.txt');
        } 'SaharaSync::X::BadContext', "Calling fetch_blob in scalar context should throw a SaharaSync::X::BadContext exception";

        throws_ok {
            $store->fetch_blob('test', 'file.txt');
        } 'SaharaSync::X::BadContext', "Calling fetch_blob in void context should throw a SaharaSync::X::BadContext exception";

        ( $blob, $revision ) = $store->fetch_blob('test', 'file.txt');
        ok ! defined($blob), "fetch_blob should return a pair of undefs for a non-existent blob";
        ok ! defined($revision), "fetch_blob should return a pair of undefs for a non-existent blob";
        ( $blob, $revision ) = $store->fetch_blob('test', 'file2.txt');
        ok ! defined($blob), "fetch_blob should return a pair of undefs for a non-existent blob";
        ok ! defined($revision), "fetch_blob should return a pair of undefs for a non-existent blob";

        throws_ok {
            ( $blob, $revision ) = $store->fetch_blob('test3', 'file.txt');
        } 'SaharaSync::X::BadUser', "fetch_blob should throw a SaharaSync::X::BadUser exception if called with a non-existent user";

        ########################## Test store_blob ###########################
        throws_ok {
            $revision = $store->store_blob('test3', 'file.txt', IO::String->new('Hello, World!'));
        } 'SaharaSync::X::BadUser', "store_blob should throw a SaharaSync::X::BadUser exception if called with a non-existent user";

        throws_ok {
            $revision = $store->store_blob('test', 'file.txt', 'Hello, World!');
        } 'SaharaSync::X::InvalidArgs', "store_blob should throw a SaharaSync::X::InvalidArgs exception if the contents do not support a read operation";

        throws_ok {
            $revision = $store->store_blob('test', 'file.txt', undef);
        } 'SaharaSync::X::InvalidArgs', "store_blob should throw a SaharaSync::X::InvalidArgs exception if the contents do not support a read operation";

        throws_ok {
            $revision = $store->store_blob('test', 'file.txt', IO::String->new('Hello, World!'), $BAD_REVISION);
        } 'SaharaSync::X::InvalidArgs', "store_blob should throw a SaharaSync::X::InvalidArgs exception if attempting to create a blob using a revision";

        $revision = $store->store_blob('test', 'file.txt', IO::String->new('Hello, World!'));
        ok $revision, "Storing a new blob should return that blob's revision";

        $revision2 = $store->store_blob('test', 'file2.txt', IO::String->new('Hello, World!'), undef);
        ok $revision2, "store_blob should accept either undef or no revision when creating a blob";

        throws_ok {
            $revision = $store->store_blob('test', 'file.txt', IO::String->new('Hello, again.'));
        } 'SaharaSync::X::InvalidArgs', "Updating a blob with no revision should throw a SaharaSync::X::InvalidArgs exception";

        throws_ok {
            $revision = $store->store_blob('test', 'file.txt', IO::String->new('Hello, again.'), undef);
        } 'SaharaSync::X::InvalidArgs', "Updating a blob with an undef revision should throw a SaharaSync::X::InvalidArgs exception";

        ( $blob, $revision2 ) = $store->fetch_blob('test', 'file.txt');
        ok defined($blob), "Fetching an existent blob should return a pair of truthy values";
        is $revision2, $revision, "The revision returned by fetch_blob should match the revision returned by the latest store_blob";
        can_ok $blob, 'getline';
        $blob = slurp_handle $blob;
        is $blob, 'Hello, World!', "The contents of the returned handler should match the last store operation";
        ( $blob, $revision ) = $store->fetch_blob('test', 'file3.txt');
        ok ! defined($blob), "Fetching a non-existent blob should return a pair of undefs";
        ok ! defined($revision), "Fetching a non-existent blob should return a pair of undefs";
        ( $blob, $revision ) = $store->fetch_blob('test2', 'file.txt');
        ok ! defined($blob), "Fetching a non-existent blob should return a pair of undefs";
        ok ! defined($revision), "Fetching a non-existent blob should return a pair of undefs";

        $revision = $store->store_blob('test2', 'file.txt', IO::String->new('Hi there'));
        ok $revision, "Creating a new blob should return its revision";
        ( $blob, $revision ) = $store->fetch_blob('test', 'file.txt');
        ok $blob, "fetch_blob should return a pair of truthy values for an existing blob";
        ok $revision, "fetch_blob should return a pair of truthy values for an existing blob";
        can_ok $blob, 'getline';
        $blob = slurp_handle $blob;
        is $blob, 'Hello, World!', "Two separate users using the same blob name should not affect one another";
        ( $blob, $revision ) = $store->fetch_blob('test2', 'file.txt');
        ok $blob, "Fetching an existent blob should return a pair of truthy values";
        ok $revision, "Fetching an existent blob should return a pair of truthy values";
        can_ok $blob, 'getline';
        $blob = slurp_handle $blob;
        is $blob, 'Hi there', "The contents of the returned handle should match the last store operation";

        ( undef, $revision ) = $store->fetch_blob('test', 'file.txt');
        $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('New contents'), $BAD_REVISION);
        ok !defined($revision2), 'Updating a blob with a non-matching revision should return undef';
        $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('New contents'), $revision);
        ok $revision2, 'Updating a blob with a matching revision should return the new revision';
        isnt $revision2, $revision, 'Updating a blob should change its revision';
        ( $blob, $revision ) = $store->fetch_blob('test', 'file.txt');
        is $revision, $revision2, 'Fetching a blob should yield its most recent revision';
        $blob = slurp_handle $blob;
        is $blob, 'New contents', 'Fetching a blob should yield its most recent contents';

        ########################## Test delete_blob #########################
        throws_ok {
            $store->delete_blob('test3', 'file.text', $BAD_REVISION);
        } 'SaharaSync::X::BadUser', 'Deleting a blob for a bad user should throw an exception';

        throws_ok {
            $store->delete_blob('test', 'file.txt');
        } 'SaharaSync::X::InvalidArgs', 'Deleting a blob with no revision should throw an exception';

        throws_ok {
            $store->delete_blob('test', 'file.txt', undef);
        } 'SaharaSync::X::InvalidArgs', 'Deleting a blob with no revision should throw an exception';

        throws_ok {
            $store->delete_blob('test', 'file4.txt', $BAD_REVISION);
        } 'SaharaSync::X::NoSuchBlob', 'Deleting a non-existent blob should throw a SaharaSync::X::NoSuchBlob exception';

        $revision = $store->delete_blob('test', 'file.txt', $BAD_REVISION);
        ok !defined($revision), 'Deleting a blob with a non-matching revision returns undef';

        ( undef, $revision ) = $store->fetch_blob('test', 'file.txt');
        $revision2 = $store->delete_blob('test', 'file.txt', $revision);
        ok $revision2, 'Deleting a blob with a matching revision returns a new revision';
        isnt $revision2, $revision, 'Deleting a blob changes the revision';

        $last_revision = $revision2;

        throws_ok {
            $revision = $store->delete_blob('test', 'file.txt', $revision2);
        } 'SaharaSync::X::NoSuchBlob', 'Deleting a once-existent blob should throw a SaharaSync::X::NoSuchBlob exception';

        ##################### Test fetch_changed_blobs ######################

        @changes = $store->fetch_changed_blobs('test');
        cmp_bag(\@changes, [uniq @changes], "fetch_changed_blobs should filter out duplicates");
        cmp_bag(\@changes, ['file.txt', 'file2.txt'], "The list of all changed blobs should include all blobs for the given user");

        @changes = $store->fetch_changed_blobs('test', undef);
        cmp_bag(\@changes, ['file.txt', 'file2.txt'], "fetch_changed_blobs should also allow a manual argument of undef");

        @changes = $store->fetch_changed_blobs('test2');

        cmp_bag(\@changes, ['file.txt'], "The list of all changed blobs should include all blobs for the given user");

        $revision = $store->store_blob('test', 'file3.txt', IO::String->new('More text'));

        @changes = $store->fetch_changed_blobs('test', $last_revision);
        cmp_bag(\@changes, ['file3.txt'], "The list of changed blobs since a revision should only include blobs changed since that revision");

        @changes = $store->fetch_changed_blobs('test', $revision);
        cmp_bag(\@changes, [], 'The list of changed blobs since the latest revision should be empty');

        @changes = $store->fetch_changed_blobs('test', undef);
        cmp_bag(\@changes, ['file.txt', 'file2.txt', 'file3.txt'], 'The list of changed blobs should include all changes');

        $last_revision = $revision;
        $revision = $store->delete_blob('test', 'file3.txt', $revision);
        @changes = $store->fetch_changed_blobs('test', $last_revision);
        cmp_bag(\@changes, ['file3.txt'], 'The list of changed blobs should include deletions');

        @changes = $store->fetch_changed_blobs('test', undef);
        cmp_bag(\@changes, ['file.txt', 'file2.txt', 'file3.txt'], 'The list of changed blobs should include deletions');

        throws_ok {
            $store->fetch_changed_blobs('test2', $last_revision);
        } 'SaharaSync::X::BadRevision', 'Calling fetch_changed_blobs with an unknown revision should throw a SaharaSync::X::BadRevision exception';

        throws_ok {
            $store->fetch_changed_blobs('test3');
        } 'SaharaSync::X::BadUser', 'Calling fetch_changed_blobs with a non-existent user should throw a SaharaSync::X::BadUser exception';

        throws_ok {
            $store->fetch_changed_blobs('test3', $BAD_REVISION);
        } 'SaharaSync::X::BadUser', 'Calling fetch_changed_blobs with a non-existent user should throw a SaharaSync::X::BadUser exception';

        $last_revision = $revision;

        $revision = $store->store_blob('test', 'file4.txt', IO::String->new('Even more text'));
        $store->delete_blob('test', 'file4.txt', $revision);

        @changes = $store->fetch_changed_blobs('test', $last_revision);
        cmp_bag(\@changes, ['file4.txt'], 'A blob that is immediately deleted should still appear in the revision list');

        ###################### Test strange blob names #######################
        $revision = $store->store_blob('test', 'dir/file.txt', IO::String->new('hey'));
        ok $revision, 'Creating a blob with a slash in its name should succeed';

        ( $blob, $revision2 ) = $store->fetch_blob('test', 'dir/file.txt');
        ok $blob, "Fetching an existent blob with a slash in its name should return a pair of truthy values";
        ok $revision2, "Fetching an existent blob with a slash in its name should return a pair of truthy values";
        can_ok $blob, 'getline';
        $blob = slurp_handle $blob;
        is $blob, 'hey', "The returned IO::Handle should match the contents of the previous store operation";
        is $revision2, $revision, "The returned revision should match the revision from store_blob";

        $revision = $store->store_blob('test', 'file-looks-like-dir/', IO::String->new('hey'));
        ok $revision, 'Creating a blob with a slash at the end should succeed';

        ( $blob, $revision2 ) = $store->fetch_blob('test', 'file-looks-like-dir/');
        ok $blob, 'Fetching an existent blob with a slash at the end should return a pair of truthy values';
        ok $revision2, 'Fetching an existent blob with a slash at the end should return a pair of truthy values';
        can_ok $blob, 'getline';
        $blob = slurp_handle $blob;
        is $blob, 'hey', 'The returned IO::Handle should match the contents of the previous store operation';
        is $revision2, $revision, 'The returned revision should match the revision from store_blob';

        ( $blob, $revision ) = $store->fetch_blob('test', 'file-looks-like-dir');
        ok !defined($blob), 'file-looks-like-dir is not file-looks-like-dir/';
        ok !defined($revision), 'file-looks-like-dir is not file-looks-like-dir/';

        ########################## Test create_user ##########################
        throws_ok {
            $store->create_user('test', 'abc123');
        } 'SaharaSync::X::BadUser', "Trying to create an existent user should throw a SaharaSync::X::BadUser exception";

        lives_ok {
            $store->create_user('test3', 'abc123');
        } "Trying to create a non-existent user should succeed";

        ########################## Test remove_user ##########################
        throws_ok {
            $store->remove_user('test4');
        } 'SaharaSync::X::BadUser', "Trying to remove a non-existent user should throw a SaharaSync::X::BadUser exception";

        lives_ok {
            $store->remove_user('test3');
        } "Trying to remove an existent user should succeed";

        ################### Test remove_user blob cleanup ####################
        $store->create_user('test3', 'abc123');
        $store->store_blob('test3', 'file.txt', IO::String->new('my text'));
        $store->remove_user('test3');
        $store->create_user('test3', 'abc123');
        ( $blob, $revision ) = $store->fetch_blob('test3', 'file.txt');
        ok !$blob, "Fetching a blob which was created by a user that has since been deleted and recreated should return undef";
        ok !$revision, "Fetching a blob which was created by a user that has since been deleted and recreated should return undef";
        @changes = $store->fetch_changed_blobs('test3');
        is_deeply(\@changes, [], "Fetching changes for a user that has been deleted and recreated should be empty");

        $store->remove_user('test3');

        ################# Try leaving our FS storage "cage" ##################
        my ( undef, $tempfile ) = tempfile('saharaXXXXX', DIR => '/tmp'); ## DBIWithFS happens to store files under /tmp/sahara...for now...
        my $contents = read_file($tempfile);
        my ( undef, undef, $filename ) = File::Spec->splitpath($tempfile);
        is $contents, '', 'assert temp file is empty';
        $revision = $store->store_blob('test', "../../$filename", IO::String->new('This better not be there!'));
        ok $revision, 'storing a strange name should still succeed';
        $contents = read_file($tempfile);
        is $contents, '', 'temp file contents should still be empty';
        unlink $tempfile;

        ( $blob, $revision2 ) = $store->fetch_blob('test', "../../$filename");
        ok $blob, 'Retrieving a strange filename should succeed';
        ok $revision2, 'Retrieving a strange filename should succeed';
        $blob = slurp_handle $blob;
        is $blob, 'This better not be there!';
        is $revision2, $revision;

        ################## Try passing a GLOB to store_blob ##################
        my $sym = gensym;
        tie *$sym, 'IO::String', 'My content';
        $revision = $store->store_blob('test', 'file.txt', $sym);
        ok $revision, 'Creating a blob with a GLOB reference should succeed';
        ( $blob, $revision2 ) = $store->fetch_blob('test', 'file.txt');
        ok $blob;
        ok $revision2;
        $blob = slurp_handle $blob;
        is $blob, 'My content';
        is $revision2, $revision;

        $store->delete_blob('test', 'file.txt', $revision);

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
