use strict;
use warnings;
use autodie qw(chmod open rename);
use parent 'Test::Class';

use AnyEvent;
use Cwd;
use File::Path qw(make_path);
use File::Temp;
use SaharaSync::Clientd::Filesystem;
use Test::Deep::NoTest qw(cmp_details deep_diag);
use Test::More;

sub fs {
    my $self = shift;

    if(@_) {
        $self->{'fs'} = shift;
    }
    return $self->{'fs'};
}

sub startup :Test(startup) {
    my ( $self ) = @_;

    $self->{'wd'} = getcwd;
}

sub setup :Test(setup) {
    my ( $self ) = @_;

    $self->{'temp'} = File::Temp->newdir;
    $self->fs(SaharaSync::Clientd::Filesystem->create_filesystem(
        root => $self->{'temp'}->dirname,
    ));
    chdir $self->{'temp'}->dirname;

    $self->{'seen_events'} = [];
    $self->{'watch_guard'} = $self->fs->on_change(sub {
        my ( @events ) = @_;

        foreach my $event (@events) {
            my $path = File::Spec->abs2rel($event->{'path'}, $self->fs->root);
            push @{ $self->{'seen_events'} }, $path;
        }
    });
}

sub teardown :Test(teardown) {
    my ( $self ) = @_;

    undef $self->{'watch_guard'};
    chdir $self->{'wd'};
    undef $self->{'temp'};
}

sub timeout {
    return 1;
}

sub expect_changes {
    my ( $self, $expected, $name ) = @_;

    my $tb = $self->builder;

    my $cond  = AnyEvent->condvar;
    my $timer = AnyEvent->timer(
        after => $self->timeout,
        cb    => sub {
            $cond->send;
        },
    );
    $cond->recv;

    my $got = $self->{'seen_events'};
    $self->{'seen_events'} = [];

    my ( $ok, $stack ) = cmp_details($got, $expected);

    $tb->ok($ok, $name);
    unless($ok) {
        $tb->diag(explain($got));
        $tb->diag(deep_diag($stack));
    }
}

sub test_self_changes :Test(3) {
    my ( $self ) = @_;

    my $fs = $self->fs;
    my $h  = $fs->open_write_handle('foo.txt');
    $h->write("Hello, World!\n");
    $h->close;

    $self->expect_changes([]);
    my $fh;
    open $fh, '<', 'foo.txt';
    my $contents = do {
        local $/;
        <$fh>;
    };
    close $fh;

    is $contents, "Hello, World!\n";

    open $fh, '>', 'bar.txt';
    print $fh  "Bar\n";
    close $fh;

    $h = $fs->open_write_handle('baz.txt');
    $h->write("Baz\n");
    $h->close;

    $self->expect_changes(['bar.txt']);
}

sub test_create_dir :Test(4) {
    my ( $self ) = @_;

    mkdir 'foo';

    $self->expect_changes([]);
    my $fh;
    open $fh, '>', 'foo/bar.txt';
    print $fh "In foo/bar.txt!\n";
    close $fh;

    $self->expect_changes(['foo/bar.txt']);

    mkdir 'bar';
    open $fh, '>', 'bar/foo.txt';
    print $fh "In bar/foo.txt!\n";
    close $fh;

    $self->expect_changes(['bar/foo.txt']);

    make_path('baz/foo/bar/quux/zen');
    open $fh, '>', 'baz/foo/bar/quux/zen/test.txt';
    print $fh "In a file with a lot of parent directories!\n";
    close $fh;

    $self->expect_changes(['baz/foo/bar/quux/zen/test.txt']);
}

sub test_attribute_changes :Test(2) {
    my ( $self ) = @_;

    my $fh;
    open $fh, '>', 'foo.txt';
    print $fh "hello\n";
    close $fh;

    $self->expect_changes(['foo.txt']);

    chmod 0400, 'foo.txt';

    $self->expect_changes([]);
}

sub test_file_changes :Test(4) {
    my ( $self ) = @_;

    my $fh;
    open $fh, '>', 'foo.txt';
    print $fh "Hello, World!\n";
    close $fh;

    $self->expect_changes(['foo.txt']);

    open $fh, '>', 'foo.txt';
    print $fh "Hello, again\n";
    close $fh;

    $self->expect_changes(['foo.txt']);

    open $fh, '>>', 'foo.txt';
    print $fh "Hello, once more\n";
    close $fh;

    $self->expect_changes(['foo.txt']);

    unlink 'foo.txt';

    $self->expect_changes(['foo.txt']);
}

sub test_moves : Test(6) {
    my ( $self ) = @_;

    my $fs = $self->fs;
    my $h  = $fs->open_write_handle('foo.txt');
    $h->write('Foo');
    $h->close;

    rename 'foo.txt', 'bar.txt';

    # the way we do things now, we just treat this operation
    # as a delete + create; we may change that later
    $self->expect_changes(['foo.txt', 'bar.txt']);

    $h = $fs->open_write_handle('baz.txt');
    $h->write('Baz');
    $h->close;

    rename 'bar.txt', 'baz.txt';

    $self->expect_changes(['bar.txt', 'baz.txt']);

    my $external_dir = File::Temp->newdir;
    open $h, '>', File::Spec->catfile($external_dir, 'foo.txt');
    print $h "External Foo\n";
    close $h;

    rename File::Spec->catfile($external_dir, 'foo.txt'), 'foo.txt';

    $self->expect_changes(['foo.txt']);

    open $h, '>', File::Spec->catfile($external_dir, 'baz.txt');
    print $h "External Bar\n";
    close $h;

    rename File::Spec->catfile($external_dir, 'baz.txt'), 'baz.txt';

    $self->expect_changes(['baz.txt']);

    rename 'baz.txt', File::Spec->catfile($external_dir, 'baz.txt');

    $self->expect_changes(['baz.txt']);

    open $h, '>', File::Spec->catfile($external_dir, 'foo.txt');
    print $h "I will be replaced\n";
    close $h;

    rename 'foo.txt', File::Spec->catfile($external_dir, 'foo.txt');

    $self->expect_changes(['foo.txt']);
}

sub test_file_write :Test(2) {
    my ( $self ) = @_;

    local $| = 1; # make sure we are actually writing stuff to disk

    my $fh;
    open $fh, '>', 'foo.txt';
    print $fh "Hello there\n";

    $self->expect_changes([]);

    close $fh;
    
    $self->expect_changes(['foo.txt']);
}

sub test_preservation :Test(2) {
    my ( $self ) = @_;

    my $fs;
    my $h;

    $fs = $self->fs;

    open $h, '>', 'foo.txt';
    print $h "Test text\n";
    close $h;

    $self->expect_changes(['foo.txt']);

    my ( $group ) = split /\s+/, $(, 2;

    subtest 'Test different chmod masks' => sub {
        my @test_perms = (
            0755,
            0644,
            0600,
            0700,
            0400,
        );
        plan tests => @test_perms * 4;

        foreach my $perm (@test_perms) {
            chmod $perm, 'foo.txt';

            $h = $fs->open_write_handle('foo.txt');
            $h->write("Test text 2\n");
            $h->close;

            $self->expect_changes([]);

            my ( $mode, $uid, $gid ) = (stat 'foo.txt')[2, 4, 5];
            $mode &= 0777;
            is $mode, $perm;
            is $uid, $<;
            is $gid, $group;
        }
    };
}

sub test_on_change_guard :Test(3) {
    my ( $self ) = @_;

    my $fh;

    $self->{'watch_guard'} = undef;

    $self->fs->on_change(sub {
        my ( @events ) = @_;

        foreach my $event (@events) {
            my $path = File::Spec->abs2rel($event->{'path'}, $self->fs->root);
            push @{ $self->{'seen_events'} }, $path;
        }
    });

    open $fh, '>', 'foo';
    print $fh "hello\n";
    close $fh;

    $self->expect_changes([]);

    my $guard = $self->fs->on_change(sub {
        my ( @events ) = @_;

        foreach my $event (@events) {
            my $path = File::Spec->abs2rel($event->{'path'}, $self->fs->root);
            push @{ $self->{'seen_events'} }, $path;
        }
    });

    open $fh, '>', 'bar';
    print $fh "hello\n";
    close $fh;

    $self->expect_changes(['bar']);

    undef $guard;

    open $fh, '>', 'baz';
    print $fh "hello\n";
    close $fh;

    $self->expect_changes([]);
}

__PACKAGE__->runtests;
