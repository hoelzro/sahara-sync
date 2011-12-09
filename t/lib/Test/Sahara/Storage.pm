package Test::Sahara::Storage;

use strict;
use warnings;
use parent 'Test::Class';
use utf8;

use IO::String;
use File::Slurp qw(read_file);
use File::Spec;
use File::Temp qw(tempfile);
use List::MoreUtils qw(uniq);
use Symbol qw(gensym);
use Test::Deep;
use Test::Exception;
use Test::More;

__PACKAGE__->SKIP_CLASS(1);

our $VERSION = '0.01';

my $BAD_REVISION = '0' x 40;

sub new {
    my ( $class, %args ) = @_;

    my $self = Test::Class::new($class);
    $self->{'arguments'} = \%args;
    return $self;
}

sub arguments {
    my ( $self ) = @_;
    return %{ $self->{'arguments'} };
}

sub slurp_handle {
    my ( $h ) = @_;

    my $contents = '';
    while(defined(my $line = $h->getline)) {
        $contents .= $line;
    }
    return $contents;
}

sub store {
    my $self = shift;

    if(@_) {
        $self->{'store'} = shift;
    }
    return $self->{'store'};
}

sub cleanup : Test(teardown) {
    my ( $self ) = @_;

    undef $self->{'store'};
}

sub test_load_user_info : Test(5) {
    my ( $self ) = @_;

    my $store = $self->store;

    my $info = $store->load_user_info('test');
    ok $info, "Verify that test user exists and yields data";
    is ref($info), 'HASH', "Verify that load_user_info returns a hash reference";
    is $info->{'username'}, 'test', "Verify that load_user_info includes a username field";
    is $info->{'password'}, 'abc123', "Verify that load_user_info includes a password field";

    $info = $store->load_user_info('test3');
    ok ! defined($info), "Verify that load_user_info returns undef for a non-existent user";
}

sub test_fetch_blob : Test(7) {
    my ( $self ) = @_;

    my $store = $self->store;

    my $blob;
    my $metadata;

    throws_ok {
        $blob = $store->fetch_blob('test', 'file.txt');
    } 'SaharaSync::X::BadContext', "Calling fetch_blob in scalar context should throw a SaharaSync::X::BadContext exception";

    throws_ok {
        $store->fetch_blob('test', 'file.txt');
    } 'SaharaSync::X::BadContext', "Calling fetch_blob in void context should throw a SaharaSync::X::BadContext exception";

    ( $blob, $metadata ) = $store->fetch_blob('test', 'file.txt');
    ok ! defined($blob), "fetch_blob should return a pair of undefs for a non-existent blob";
    ok ! defined($metadata), "fetch_blob should return a pair of undefs for a non-existent blob";
    ( $blob, $metadata ) = $store->fetch_blob('test', 'file2.txt');
    ok ! defined($blob), "fetch_blob should return a pair of undefs for a non-existent blob";
    ok ! defined($metadata), "fetch_blob should return a pair of undefs for a non-existent blob";

    throws_ok {
        ( $blob, $metadata ) = $store->fetch_blob('test3', 'file.txt');
    } 'SaharaSync::X::BadUser', "fetch_blob should throw a SaharaSync::X::BadUser exception if called with a non-existent user";
}

sub test_store_blob : Test(34) {
    my ( $self ) = @_;

    my $store = $self->store;

    my $revision;
    my $revision2;
    my $blob;
    my $metadata;

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
    } 'SaharaSync::X::InvalidArgs', "store_blob should throw a SaharaSync::X::InvalidArgs exception if attempting to use a string for metadata";

    $revision = $store->store_blob('test', 'file.txt', IO::String->new('Hello, World!'), { revision => $BAD_REVISION });
    ok !defined($revision), "store_blob should return undef if attempting to create a blob using a revision";

    $revision = $store->store_blob('test', 'file.txt', IO::String->new('Hello, World!'));
    ok $revision, "Storing a new blob should return that blob's revision";

    $revision2 = $store->store_blob('test', 'file2.txt', IO::String->new('Hello, World!'), undef);
    ok $revision2, "store_blob should accept either undef or no revision when creating a blob";

    $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('Hello, again.'));
    ok !defined($revision2), "Updating a blob with no revision should return undef";

    $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('Hello, again.'), undef);
    ok !defined($revision2), "Updating a blob with undef metadata should return undef";

    ( $blob, $metadata ) = $store->fetch_blob('test', 'file.txt');
    ok defined($blob), "Fetching an existent blob should return a pair of truthy values";
    isa_ok $metadata, 'HASH', 'Fetching an existent blob should return its metadata as a hash';
    $revision2 = $metadata->{'revision'};
    is $revision2, $revision, "The revision returned by fetch_blob should match the revision returned by the latest store_blob";
    can_ok $blob, 'getline';
    $blob = slurp_handle $blob;
    is $blob, 'Hello, World!', "The contents of the returned handler should match the last store operation";
    ( $blob, $metadata ) = $store->fetch_blob('test', 'file3.txt');
    ok ! defined($blob), "Fetching a non-existent blob should return a pair of undefs";
    ok ! defined($metadata), "Fetching a non-existent blob should return a pair of undefs";
    ( $blob, $metadata ) = $store->fetch_blob('test2', 'file.txt');
    ok ! defined($blob), "Fetching a non-existent blob should return a pair of undefs";
    ok ! defined($metadata), "Fetching a non-existent blob should return a pair of undefs";

    $revision = $store->store_blob('test2', 'file.txt', IO::String->new('Hi there'));
    ok $revision, "Creating a new blob should return its revision";
    ( $blob, $metadata ) = $store->fetch_blob('test', 'file.txt');
    $revision = $metadata->{'revision'};
    ok $blob, "fetch_blob should return a pair of truthy values for an existing blob";
    ok $metadata, "fetch_blob should return a pair of truthy values for an existing blob";
    ok $metadata->{'revision'}, "fetch_blobs should return metadata with a revision key";
    can_ok $blob, 'getline';
    $blob = slurp_handle $blob;
    is $blob, 'Hello, World!', "Two separate users using the same blob name should not affect one another";
    ( $blob, $metadata ) = $store->fetch_blob('test2', 'file.txt');
    ok $blob, "Fetching an existent blob should return a pair of truthy values";
    ok $metadata, "Fetching an existent blob should return a pair of truthy values";
    ok $metadata->{'revision'}, "fetch_blobs should return metadata with a revision key";
    $revision = $metadata->{'revision'};
    can_ok $blob, 'getline';
    $blob = slurp_handle $blob;
    is $blob, 'Hi there', "The contents of the returned handle should match the last store operation";

    ( undef, $metadata ) = $store->fetch_blob('test', 'file.txt');
    $revision = $metadata->{'revision'};
    $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('New contents'), { revision => $BAD_REVISION });
    ok !defined($revision2), 'Updating a blob with a non-matching revision should return undef';
    $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('New contents'), { revision => $revision });
    ok $revision2, 'Updating a blob with a matching revision should return the new revision';
    isnt $revision2, $revision, 'Updating a blob should change its revision';
    ( $blob, $metadata ) = $store->fetch_blob('test', 'file.txt');
    $revision = $metadata->{'revision'};
    is $revision, $revision2, 'Fetching a blob should yield its most recent revision';
    $blob = slurp_handle $blob;
    is $blob, 'New contents', 'Fetching a blob should yield its most recent contents';
}

sub test_delete_blob : Test(8) {
    my ( $self ) = @_;

    my $store = $self->store;

    my $revision;
    my $revision2;
    my $metadata;

    $revision = $store->store_blob('test', 'file.txt', IO::String->new('Test content'));

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

    ( undef, $metadata ) = $store->fetch_blob('test', 'file.txt');
    $revision = $metadata->{'revision'};
    $revision2 = $store->delete_blob('test', 'file.txt', $revision);
    ok $revision2, 'Deleting a blob with a matching revision returns a new revision';
    isnt $revision2, $revision, 'Deleting a blob changes the revision';

    throws_ok {
        $revision = $store->delete_blob('test', 'file.txt', $revision2);
    } 'SaharaSync::X::NoSuchBlob', 'Deleting a once-existent blob should throw a SaharaSync::X::NoSuchBlob exception';
}

sub test_fetch_changed_blobs : Test(13) {
    my ( $self ) = @_;

    my $store = $self->store;

    my @changes;
    my $metadata;
    my $revision;

    $revision = $store->store_blob('test', 'file.txt', IO::String->new('Test content'));
    my $deleted_revision = $store->delete_blob('test', 'file.txt', $revision);

    my $file2_revision = $store->store_blob('test', 'file2.txt', IO::String->new('Test content 2'));
    my $last_revision  = $file2_revision;

    $store->store_blob('test2', 'file.txt', IO::String->new('Test content: user 2'));

    @changes = $store->fetch_changed_blobs('test');
    cmp_bag([ map { $_->{'name'} } @changes ], [uniq map { $_->{'name'} } @changes], "fetch_changed_blobs should filter out duplicates");
    ( undef, $metadata ) = $store->fetch_blob('test', 'file2.txt');
    cmp_bag(\@changes, [{ name => 'file.txt', is_deleted => 1, revision => $deleted_revision }, { name => 'file2.txt', revision => $file2_revision }],
        "The list of all changed blobs should include all blobs for the given user");

    @changes = $store->fetch_changed_blobs('test', undef);
    cmp_bag(\@changes, [{ name => 'file.txt', is_deleted => 1, revision => $deleted_revision }, { name => 'file2.txt', revision => $file2_revision}],
        "fetch_changed_blobs should also allow a manual argument of undef");

    @changes = $store->fetch_changed_blobs('test2');

    ( undef, $metadata ) = $store->fetch_blob('test2', 'file.txt');
    cmp_bag(\@changes, [{ name => 'file.txt', revision => $metadata->{'revision'}}], "The list of all changed blobs should include all blobs for the given user");

    $revision = $store->store_blob('test', 'file3.txt', IO::String->new('More text'));

    @changes = $store->fetch_changed_blobs('test', $last_revision);
    cmp_bag(\@changes, [{ name => 'file3.txt', revision => $revision}], "The list of changed blobs since a revision should only include blobs changed since that revision");

    @changes = $store->fetch_changed_blobs('test', $revision);
    cmp_bag(\@changes, [], 'The list of changed blobs since the latest revision should be empty');

    @changes = $store->fetch_changed_blobs('test', undef);
    cmp_bag(\@changes, [{
        name       => 'file.txt',
        is_deleted => 1,
        revision   => $deleted_revision,
    }, {
        name     => 'file2.txt',
        revision => $file2_revision,
    }, {
        name     => 'file3.txt',
        revision => $revision,
    }], 'The list of changed blobs should include all changes');


    $last_revision = $revision;
    $revision = $store->delete_blob('test', 'file3.txt', $revision);
    @changes = $store->fetch_changed_blobs('test', $last_revision);
    cmp_bag(\@changes, [{ name => 'file3.txt', is_deleted => 1, revision => $revision }], 'The list of changed blobs should include deletions');

    @changes = $store->fetch_changed_blobs('test', undef);
    cmp_bag(\@changes, [{
        name       => 'file.txt', 
        is_deleted => 1,
        revision   => $deleted_revision,
    }, {
        name     => 'file2.txt', 
        revision => $file2_revision,
    }, {
        name       => 'file3.txt',
        is_deleted => 1,
        revision   => $revision,
    }], 'The list of changed blobs should include deletions');

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
    $revision = $store->delete_blob('test', 'file4.txt', $revision);

    @changes = $store->fetch_changed_blobs('test', $last_revision);
    cmp_bag(\@changes, [{ name => 'file4.txt', is_deleted => 1, revision => $revision }], 'A blob that is immediately deleted should still appear in the revision list');
}

sub test_strange_blob_names : Test(16) {
    my ( $self ) = @_;

    my $store = $self->store;

    my $revision = $store->store_blob('test', 'dir/file.txt', IO::String->new('hey'));
    ok $revision, 'Creating a blob with a slash in its name should succeed';

    my ( $blob, $metadata ) = $store->fetch_blob('test', 'dir/file.txt');
    ok $blob, "Fetching an existent blob with a slash in its name should return a pair of truthy values";
    ok $metadata, "Fetching an existent blob with a slash in its name should return a pair of truthy values";
    ok $metadata->{'revision'}, "fetch_blobs should return metadata with a revision key";
    my $revision2 = $metadata->{'revision'};
    can_ok $blob, 'getline';
    $blob = slurp_handle $blob;
    is $blob, 'hey', "The returned IO::Handle should match the contents of the previous store operation";
    is $revision2, $revision, "The returned revision should match the revision from store_blob";

    $revision = $store->store_blob('test', 'file-looks-like-dir/', IO::String->new('hey'));
    ok $revision, 'Creating a blob with a slash at the end should succeed';

    ( $blob, $metadata ) = $store->fetch_blob('test', 'file-looks-like-dir/');
    $revision2 = $metadata->{'revision'};
    ok $blob, 'Fetching an existent blob with a slash at the end should return a pair of truthy values';
    ok $metadata, 'Fetching an existent blob with a slash at the end should return a pair of truthy values';
    ok $metadata->{'revision'}, "fetch_blobs should return metadata with a revision key";
    $revision2 = $metadata->{'revision'};
    can_ok $blob, 'getline';
    $blob = slurp_handle $blob;
    is $blob, 'hey', 'The returned IO::Handle should match the contents of the previous store operation';
    is $revision2, $revision, 'The returned revision should match the revision from store_blob';

    ( $blob, $metadata ) = $store->fetch_blob('test', 'file-looks-like-dir');
    ok !defined($blob), 'file-looks-like-dir is not file-looks-like-dir/';
    ok !defined($metadata), 'file-looks-like-dir is not file-looks-like-dir/';
}

sub test_create_user : Test(2) {
    my ( $self ) = @_;

    my $store = $self->store;

    throws_ok {
        $store->create_user('test', 'abc123');
    } 'SaharaSync::X::BadUser', "Trying to create an existent user should throw a SaharaSync::X::BadUser exception";

    lives_ok {
        $store->create_user('test3', 'abc123');
    } "Trying to create a non-existent user should succeed";
}

sub test_remove_user : Test(2) {
    my ( $self ) = @_;

    my $store = $self->store;

    throws_ok {
        $store->remove_user('test4');
    } 'SaharaSync::X::BadUser', "Trying to remove a non-existent user should throw a SaharaSync::X::BadUser exception";

    lives_ok {
        $store->remove_user('test');
    } "Trying to remove an existent user should succeed";
}

sub test_remove_user_cleanup : Test(3) {
    my ( $self ) = @_;

    my $store = $self->store;

    $store->store_blob('test', 'file.txt', IO::String->new('my text'));
    $store->remove_user('test');
    $store->create_user('test', 'abc123');
    my ( $blob, $metadata ) = $store->fetch_blob('test', 'file.txt');
    ok !$blob, "Fetching a blob which was created by a user that has since been deleted and recreated should return undef";
    ok !$metadata, "Fetching a blob which was created by a user that has since been deleted and recreated should return undef";
    my @changes = $store->fetch_changed_blobs('test');
    is_deeply(\@changes, [], "Fetching changes for a user that has been deleted and recreated should be empty");
}

sub test_fs_cage : Test(8) {
    my ( $self ) = @_;

    my $store = $self->store;

    my ( undef, $tempfile ) = tempfile('saharaXXXXX', DIR => '/tmp'); ## DBIWithFS happens to store files under /tmp/sahara...for now...
    my $contents = read_file($tempfile);
    my ( undef, undef, $filename ) = File::Spec->splitpath($tempfile);
    is $contents, '', 'assert temp file is empty';
    my $revision = $store->store_blob('test', "../../$filename", IO::String->new('This better not be there!'));
    ok $revision, 'storing a strange name should still succeed';
    $contents = read_file($tempfile);
    is $contents, '', 'temp file contents should still be empty';
    unlink $tempfile;

    my ( $blob, $metadata ) = $store->fetch_blob('test', "../../$filename");
    ok $blob, 'Retrieving a strange filename should succeed';
    ok $metadata, 'Retrieving a strange filename should succeed';
    ok $metadata->{'revision'}, "fetch_blobs should return metadata with a revision key";
    my $revision2 = $metadata->{'revision'};
    $blob = slurp_handle $blob;
    is $blob, 'This better not be there!';
    is $revision2, $revision;
}

sub test_store_glob : Test(6) {
    my ( $self ) = @_;

    my $store = $self->store;

    my $sym = gensym;
    tie *$sym, 'IO::String', 'My content';
    my $revision = $store->store_blob('test', 'file.txt', $sym);
    ok $revision, 'Creating a blob with a GLOB reference should succeed';
    my ( $blob, $metadata ) = $store->fetch_blob('test', 'file.txt');
    ok $blob;
    ok $metadata;
    ok $metadata->{'revision'};
    my $revision2 = $metadata->{'revision'};
    $blob = slurp_handle $blob;
    is $blob, 'My content';
    is $revision2, $revision;
}

sub test_store_delete_store : Test(8) {
    my ( $self ) = @_;

    my $store = $self->store;

    my $revision = $store->store_blob('test', 'file.txt', IO::String->new('Test text'));
    my $revision2 = $store->delete_blob('test', 'file.txt', $revision);
    $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('Test text'), { revision => $revision2 });
    ok !defined($revision2), 'Storing a new blob (but previously deleted) blob with a revision should return undef';
    lives_ok {
        $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('Test text'));
    } 'Storing a new (but previously deleted) blob without a revision should succeed';
    ok $revision2, 'Storing a new (but previously deleted) blob without a revision should succeed';
    isnt $revision2, $revision, "A new (but previously deleted) blob's revision should differ from its original";

    $revision = $store->store_blob('test', 'file.txt', IO::String->new('More text!'));
    ok !defined($revision), 'Storing another revision to a previously deleted blob with no revision should return undef';

    lives_ok {
        $revision = $store->store_blob('test', 'file.txt', IO::String->new('More text!'), { revision => $revision2 });
    } 'Storing another revision to a previously deleted blob should succeed';
    ok $revision, 'Storing another revision to a previously deleted blob should succeed';
    isnt $revision, $revision2, 'Storing a blob should change its revision';
}

sub test_utf8_filenames : Test(4) {
    my ( $self ) = @_;

    my $store = $self->store;

    my $revision;
    lives_ok {
        $revision = $store->store_blob('test', 'über', IO::String->new('Fake text'));
    } 'UTF-8 filenames should save ok';
    my ( $blob, $metadata ) = $store->fetch_blob('test', 'über');
    ok $blob, 'Fetching a UTF-8 filename should succeed';
    ok $metadata, 'Fetching a UTF-8 filename should succeed';
    my $revision2 = $metadata->{'revision'};
    is $revision2, $revision, 'A fetched revision for a UTF-8 filename should match its most recent store';
}

sub test_metadata : Test(15) {
    my ( $self ) = @_;

    my $store = $self->store;
    my $revision  = $store->store_blob('test', 'file.txt', IO::String->new('Test text'), { foo => 1 });
    my $revision2 = $revision;
    ok $revision;
    my ( $blob, $metadata ) = $store->fetch_blob('test', 'file.txt');
    ok $blob;
    is_deeply($metadata, { foo => 1, revision => $revision }, "Adding metadata to a new blob should show up on subsequent fetches");
    $revision = $store->store_blob('test', 'file.txt', IO::String->new('Test text 2'), { bar => 2 });
    ok !defined($revision), "Updating a blob with no revision should fail";
    $revision = $store->store_blob('test', 'file.txt', IO::String->new('Test text 2'), { bar => 2, revision => $revision2 });
    ( $blob, $metadata ) = $store->fetch_blob('test', 'file.txt');
    ok $blob;
    is_deeply($metadata, { foo => 1, bar => 2, revision => $revision }, "Updating a blob preserves old metadata");
    $revision = $store->store_blob('test', 'file.txt', IO::String->new('Test text 3'), { Foo => 3, revision => $revision });
    ( $blob, $metadata ) = $store->fetch_blob('test', 'file.txt');
    ok $blob;
    is_deeply($metadata, { foo => 3, bar => 2, revision => $revision }, "Metadata are case-insensitive");
    ok $store->delete_blob('test', 'file.txt', $revision);
    $revision  = $store->store_blob('test', 'file.txt', IO::String->new('Test text'));
    ( $blob, $metadata ) = $store->fetch_blob('test', 'file.txt');
    ok $blob;
    is_deeply($metadata, { revision => $revision }, "Deleting a blob deletes all attached metadata");

    ok $store->delete_blob('test', 'file.txt', $revision);
    throws_ok {
        $store->store_blob('test', 'file.txt', IO::String->new('Test text'), { 'a' x 256 => 1 });
    } 'SaharaSync::X::InvalidArgs', "Storing metadata with a key longer than 255 characters should fail";

    throws_ok {
        $store->store_blob('test', 'file.txt', IO::String->new('Test text'), { foo => 'a' x 256 });
    } 'SaharaSync::X::InvalidArgs', "Storing metadata with a value longer than 255 characters should fail";

    lives_ok {
        $store->store_blob('test', 'file.txt', IO::String->new('Test text'), { 'a' x 255 => 'b' x 255 });
    } "Storing metadata with 255 characters or less for the keys or values should succeed";
}

sub test_utf8_metadata : Test(2) {
    my ( $self ) = @_;

    my $store = $self->store;

    my $revision = $store->store_blob('test', 'file.txt', IO::String->new('Test text'), { 'über' => 'schön' });
    ok $revision;
    my ( undef, $metadata ) = $store->fetch_blob('test', 'file.txt');

    is_deeply($metadata, { revision => $revision, 'über' => 'schön' }, "UTF-8 metadata should be preserved");
}

sub test_revision_function : Test(7) {
    my ( $self ) = @_;

    my $store = $self->store;

    my $revision = $store->store_blob('test', 'file.txt', IO::String->new('Test text'), { foo => 1 });
    my $revision2 = $store->store_blob('test2', 'file.txt', IO::String->new('Test text'), { foo => 1 });
    is $revision2, $revision, "Blob revisions are a deterministic function of the name, contents, metadata, and previous revision";

    $store->remove_user('test');
    $store->create_user('test', 'abc123');
    $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('Test text'), { foo => 1 });
    is $revision2, $revision, "Blob revisions are a deterministic function of the name, contents, metadata, and previous revision";

    $store->remove_user('test');
    $store->create_user('test', 'abc123');
    $revision2 = $store->store_blob('test', 'file2.txt', IO::String->new('Test text'), { foo => 1 });
    isnt $revision2, $revision, "Blob revisions are a deterministic function of the name, contents, metadata, and previous revision";

    $store->remove_user('test');
    $store->create_user('test', 'abc123');
    $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('Test text 2'), { foo => 1 });
    isnt $revision2, $revision, "Blob revisions are a deterministic function of the name, contents, metadata, and previous revision";

    $store->remove_user('test');
    $store->create_user('test', 'abc123');
    $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('Test text'), { foo => 2 });
    isnt $revision2, $revision, "Blob revisions are a deterministic function of the name, contents, metadata, and previous revision";

    $store->remove_user('test');
    $store->create_user('test', 'abc123');
    $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('Test text'), { Foo => 1 });
    is $revision2, $revision, "Blob revisions are a deterministic function of the name, contents, metadata, and previous revision";

    $store->remove_user('test');
    $store->create_user('test', 'abc123');
    $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('Test text'), { bar => 1 });
    isnt $revision2, $revision, "Blob revisions are a deterministic function of the name, contents, metadata, and previous revision";
}

sub test_fetch_changed_blobs_metadata : Test(10) {
    my ( $self ) = @_;

    my $store = $self->store;

    my $revision = $store->store_blob('test', 'file.txt', IO::String->new('Test text'), { foo => 1 });
    my @changes  = $store->fetch_changed_blobs('test', undef);
    cmp_bag(\@changes, [{
        name     => 'file.txt',
        revision => $revision,
    }], 'Omitting the metadata parameter should return no extra metadata');
    @changes  = $store->fetch_changed_blobs('test', undef, undef);
    cmp_bag(\@changes, [{
        name     => 'file.txt',
        revision => $revision,
    }], 'Requesting no metadata should return no extra metadata');
    @changes  = $store->fetch_changed_blobs('test', undef, []);
    cmp_bag(\@changes, [{
        name     => 'file.txt',
        revision => $revision,
    }], 'Requesting no metadata should return no extra metadata');
    @changes  = $store->fetch_changed_blobs('test', undef, ['foo']);
    cmp_bag(\@changes, [{
        name     => 'file.txt',
        revision => $revision,
        foo      => 1,
    }], 'Requesting existing metadata returns that metadata');
    @changes  = $store->fetch_changed_blobs('test', undef, ['bar']);
    cmp_bag(\@changes, [{
        name     => 'file.txt',
        revision => $revision,
    }], 'Requesting non-existing metadata omits those metadata from the results');

    my $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('Test text 2'), { foo => 2, revision => $revision });
    my $revision3 = $store->store_blob('test', 'file.txt', IO::String->new('Test text 3'), { foo => 3, revision => $revision2 });
    @changes      = $store->fetch_changed_blobs('test', undef, ['foo']);
    cmp_bag(\@changes, [{
        name     => 'file.txt',
        revision => $revision3,
        foo      => 3,
    }], 'Only the latest metadata are returned');

    @changes      = $store->fetch_changed_blobs('test', $revision, ['foo']);
    cmp_bag(\@changes, [{
        name     => 'file.txt',
        revision => $revision3,
        foo      => 3,
    }], 'Only the latest metadata are returned');

    @changes      = $store->fetch_changed_blobs('test', $revision2, ['foo']);
    cmp_bag(\@changes, [{
        name     => 'file.txt',
        revision => $revision3,
        foo      => 3,
    }], 'Only the latest metadata are returned');

    my $deleted_revision = $store->delete_blob('test', 'file.txt', $revision3);

    @changes      = $store->fetch_changed_blobs('test', $revision3, ['foo']);
    cmp_bag(\@changes, [{
        name       => 'file.txt',
        is_deleted => 1,
        revision   => $deleted_revision,
        foo        => 3,
    }], 'No extra metadata are returned for deleted blobs');

    @changes      = $store->fetch_changed_blobs('test', $revision2, ['foo']);
    cmp_bag(\@changes, [{
        name       => 'file.txt',
        is_deleted => 1,
        revision   => $deleted_revision,
        foo        => 3,
    }], 'All requested metadata are returned for deleted blobs');
}

sub test_too_much_metadata_bug : Test {
    my ( $self ) = @_;

    my $file_revision;
    my $file1_revision;
    my $file2_revision;
    my $store = $self->store;

    $file_revision = $store->store_blob('test', 'file.txt',
        IO::String->new('file.txt content'), { foo => 3 });
    $file_revision = $store->delete_blob('test', 'file.txt', $file_revision);

    $file1_revision = $store->store_blob('test', 'file1.txt',
        IO::String->new('file1.txt content'), { foo => 4 });
    $file2_revision = $store->store_blob('test', 'file2.txt',
        IO::String->new('file2.txt content'), { foo => 5 });

    my @changes = $store->fetch_changed_blobs('test', $file1_revision, ['foo']);

    is_deeply(\@changes, [{
        name     => 'file2.txt',
        revision => $file2_revision,
        foo      => 5,
    }], "metadata for blobs not modified since revision should not be present in changelog");
}

sub test_changes_since_deletion : Test {
    my ( $self ) = @_;

    my $revision;
    my $revision2;
    my $store = $self->store;

    $revision = $store->store_blob('test', 'file.txt', IO::String->new('Test Content'));
    $revision = $store->delete_blob('test', 'file.txt', $revision);

    $revision2 = $store->store_blob('test', 'file.txt', IO::String->new('Test Content'));

    my @changes = $store->fetch_changed_blobs('test', $revision);

    is_deeply(\@changes, [{
        name     => 'file.txt',
        revision => $revision2,
    }], "You should be able to get changes since a deletion");
}

## code duplication!
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

sub test_change_ordering : Test {
    my ( $self ) = @_;

    my @names = (
        'file.txt',
        'file1.txt',
        'file2.txt',
    );

    subtest '' => sub {
        plan tests => factorial(scalar @names) * 2;

        foreach my $perm (permutations @names) {
            my @revisions;

            $self->create_impl;
            my $store = $self->store;


            foreach my $blob (@$perm) {
                push @revisions, $store->store_blob('test', $blob,
                    IO::String->new("In $blob"));
            }

            my @changes;
            my @expected;

            @changes = $store->fetch_changed_blobs('test', undef);

            @expected = map {
                {
                    name     => $perm->[$_],
                    revision => $revisions[$_],
                }
            } (0..$#revisions);

            is_deeply(\@changes, \@expected);

            @changes = $store->fetch_changed_blobs('test', $revisions[0]);

            @expected = map {
                {
                    name     => $perm->[$_],
                    revision => $revisions[$_],
                }
            } (1..$#revisions);

            is_deeply(\@changes, \@expected);
        }
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
