use strict;
use warnings;
use autodie qw(chmod open rename);
use parent 'Test::Class::AnyEvent';

use AnyEvent;
use Cwd;
use File::Path qw(make_path);
use File::Slurp qw(append_file read_file write_file);
use File::Temp;
use List::MoreUtils qw(all);
use SaharaSync::Clientd::SyncDir;
use Test::Deep::NoTest qw(bag cmp_details deep_diag);
use Test::More;

sub sd {
    my $self = shift;

    if(@_) {
        $self->{'sd'} = shift;
    }
    return $self->{'sd'};
}

sub create_sync_dir {
    my ( $self ) = @_;

    my $sd = SaharaSync::Clientd::SyncDir->create_syncdir(
        root => $self->{'temp'}->dirname,
    );
    $self->sd($sd);

    $self->{'seen_events'} = [];
    $self->{'watch_guard'} = $sd->on_change(sub {
        my ( $sd, $event, $continuation ) = @_;

        my $path = File::Spec->abs2rel($event->{'path'}, $sd->root);
        push @{ $self->{'seen_events'} }, $path;

        unless(defined $continuation) {
            use Carp qw(longmess);
            diag(longmess());
        }
        $continuation->();
    });

    return $sd;
}

sub startup :Test(startup) {
    my ( $self ) = @_;

    $self->{'wd'} = getcwd;
}

sub setup :Test(setup) {
    my ( $self ) = @_;

    $self->{'temp'} = File::Temp->newdir;
    chdir $self->{'temp'}->dirname;
    $self->create_sync_dir;
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
    my ( $self, $expected, $as_bag, $name ) = @_;

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

    if($as_bag) {
        $expected = bag(@$expected);
    }

    my ( $ok, $stack ) = cmp_details($got, $expected);

    $tb->ok($ok, $name);
    unless($ok) {
        $tb->diag(explain($got));
        $tb->diag(deep_diag($stack));
    }
}

sub octal {
    my ( $n ) = @_;

    return sprintf('0%o', $n);
}

sub test_self_changes :Test(5) {
    my ( $self ) = @_;

    my $sd = $self->sd;
    my $h  = $sd->open_write_handle('foo.txt');
    $h->write("Hello, World!\n");
    $h->close(sub {
        my ( $ok, $error ) = @_;
        ok $ok or diag $error;
    });

    $self->expect_changes([]);
    my $contents = read_file 'foo.txt';

    is $contents, "Hello, World!\n";

    write_file 'bar.txt', "Bar\n";

    $h = $sd->open_write_handle('baz.txt');
    $h->write("Baz\n");
    $h->close(sub {
        my ( $ok, $error ) = @_;
        ok $ok or diag $error;
    });

    $self->expect_changes(['bar.txt']);
}

sub test_create_dir :Test(4) {
    my ( $self ) = @_;

    mkdir 'foo';

    $self->expect_changes([]);
    write_file 'foo/bar.txt', "In foo/bar.txt!\n";

    $self->expect_changes(['foo/bar.txt']);

    mkdir 'bar';
    write_file 'bar/foo.txt', "In bar/foo.txt!\n";

    $self->expect_changes(['bar/foo.txt']);

    make_path('baz/foo/bar/quux/zen');
    write_file 'baz/foo/bar/quux/zen/test.txt',"In a file with a lot of parent directories!\n";

    $self->expect_changes(['baz/foo/bar/quux/zen/test.txt']);
}

sub test_attribute_changes :Test(2) {
    my ( $self ) = @_;

    my $fh;
    write_file 'foo.txt', "hello\n";

    $self->expect_changes(['foo.txt']);

    chmod 0400, 'foo.txt';

    $self->expect_changes([]);
}

sub test_file_changes :Test(4) {
    my ( $self ) = @_;

    write_file 'foo.txt', "Hello, World!\n";

    $self->expect_changes(['foo.txt']);

    write_file 'foo.txt', "Hello, again\n";

    $self->expect_changes(['foo.txt']);

    append_file 'foo.txt', "Hello once more\n";

    $self->expect_changes(['foo.txt']);

    unlink 'foo.txt';

    $self->expect_changes(['foo.txt']);
}

sub test_moves : Test(8) {
    my ( $self ) = @_;

    my $sd = $self->sd;
    my $h  = $sd->open_write_handle('foo.txt');
    $h->write('Foo');
    $h->close(sub {
        my ( $ok, $error ) = @_;

        ok $ok or diag $error;
    });

    rename 'foo.txt', 'bar.txt';

    # the way we do things now, we just treat this operation
    # as a delete + create; we may change that later
    $self->expect_changes(['foo.txt', 'bar.txt']);

    $h = $sd->open_write_handle('baz.txt');
    $h->write('Baz');
    $h->close(sub {
        my ( $ok, $error ) = @_;

        ok $ok or diag $error;
    });

    rename 'bar.txt', 'baz.txt';

    $self->expect_changes(['bar.txt', 'baz.txt']);

    my $external_dir = File::Temp->newdir;
    write_file(File::Spec->catfile($external_dir, 'foo.txt'), "External Foo\n");

    rename File::Spec->catfile($external_dir, 'foo.txt'), 'foo.txt';

    $self->expect_changes(['foo.txt']);

    write_file(File::Spec->catfile($external_dir, 'baz.txt'), "External Baz\n");

    rename File::Spec->catfile($external_dir, 'baz.txt'), 'baz.txt';

    $self->expect_changes(['baz.txt']);

    rename 'baz.txt', File::Spec->catfile($external_dir, 'baz.txt');

    $self->expect_changes(['baz.txt']);

    write_file(File::Spec->catfile($external_dir, 'foo.txt'), "I will be replaced\n");

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

    my $sd;
    my $h;

    $sd = $self->sd;

    write_file 'foo.txt', "Test text\n";

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
        plan tests => @test_perms * 5;

        foreach my $perm (@test_perms) {
            chmod $perm, 'foo.txt';

            $h = $sd->open_write_handle('foo.txt');
            $h->write("Test text 2\n");
            $h->close(sub {
                my ( $ok, $error ) = @_;

                ok $ok or diag $error;
            });

            $self->expect_changes([]);

            my ( $mode, $uid, $gid ) = (stat 'foo.txt')[2, 4, 5];
            $mode &= 0777;
            is octal($mode), octal($perm);
            is $uid, $<;
            is $gid, $group;
        }
    };
}

sub test_on_change_guard :Test(7) {
    my ( $self ) = @_;

    my $fh;

    $self->{'watch_guard'} = undef;

    $self->sd->on_change(sub {
        my ( $sd, $event, $continuation ) = @_;

        my $path = File::Spec->abs2rel($event->{'path'}, $sd->root);
        push @{ $self->{'seen_events'} }, $path;

        $continuation->();
    });

    write_file 'foo', "hello\n";

    $self->expect_changes([]);

    unlink 'foo';

    $self->expect_changes([]);

    my $guard = $self->sd->on_change(sub {
        my ( $sd, $event, $continuation ) = @_;

        my $path = File::Spec->abs2rel($event->{'path'}, $sd->root);
        push @{ $self->{'seen_events'} }, $path;

        $continuation->();
    });

    write_file 'bar', "hello\n";

    $self->expect_changes(['foo', 'bar']);

    undef $guard;

    write_file 'baz', "hello\n";

    $self->expect_changes([]);

    unlink 'bar';
    unlink 'baz';

    $self->expect_changes([]);

    $guard = $self->sd->on_change(sub {
        my ( $sd, $event, $continuation ) = @_;

        my $path = File::Spec->abs2rel($event->{'path'}, $sd->root);
        push @{ $self->{'seen_events'} }, $path;

        $continuation->();
    });

    $self->expect_changes(['foo', 'bar', 'baz']);

    $self->sd(undef);

    write_file 'quux', "hello\n";

    $self->expect_changes([]);
}

sub test_handle_cancel :Test(2) {
    my ( $self ) = @_;

    my $h = $self->sd->open_write_handle('foo.txt');
    $h->write("Hey you guys");
    $h->cancel;

    $self->expect_changes([]);
    ok(! -f "foo.txt");
}

sub test_delete_file :Test(5) {
    my ( $self ) = @_;

    my $sd = $self->sd;
    my $fh;

    write_file 'foo.txt', "hello\n";

    $self->expect_changes(['foo.txt']);

    $sd->unlink('foo.txt', sub {
        my ( $ok, $error ) = @_;

        ok $ok;
        ok !defined($error);
    });

    $self->expect_changes([]);
    ok ! -e 'foo.txt';
}

sub test_preexisting_files :Test {
    my ( $self ) = @_;

    $self->sd(undef);

    write_file 'foo.txt', "Hello from foo";
    write_file 'bar.txt', "Hello from bar";
    write_file 'baz.txt', "Hello from baz";

    $self->create_sync_dir;

    $self->expect_changes(['foo.txt', 'bar.txt', 'baz.txt'], 1);
}

sub test_offline_update :Test(2) {
    my ( $self ) = @_;

    write_file 'foo.txt', "Hello";

    $self->expect_changes(['foo.txt']);

    $self->sd(undef);

    write_file 'foo.txt', "Hello, again";

    $self->create_sync_dir;

    $self->expect_changes(['foo.txt']);
}

sub test_offline_static :Test(2) {
    my ( $self ) = @_;

    write_file 'foo.txt', "Hello";

    $self->expect_changes(['foo.txt']);

    $self->sd(undef);

    $self->create_sync_dir;

    $self->expect_changes([]);
}

sub test_self_updates :Test(3) {
    my ( $self) = @_;

    my $h = $self->sd->open_write_handle('foo.txt');
    $h->write("Hello!\n");
    $h->close(sub {
        my ( $ok, $error ) = @_;

        ok $ok or diag $error;
    });

    $self->sd(undef);

    $self->expect_changes([]);

    $self->create_sync_dir;

    $self->expect_changes([]);
}

sub test_move_file :Test(6) {
    my ( $self ) = @_;

    my $sd = $self->sd;

    write_file 'foo.txt', "hello\n";

    $self->expect_changes(['foo.txt']);

    $sd->rename('foo.txt', 'bar.txt', sub {
        my ( $ok, $error ) = @_;

        ok $ok or diag $error;
    });

    $self->expect_changes([]);
    ok -e 'bar.txt';
    ok !(-e 'foo.txt');
    my $content = read_file 'bar.txt';
    is $content, "hello\n";
}

sub perform_conflict_test {
    my ( $self, %params ) = @_;

    local $self->{'seen_conflicts'} = []; # we're expecting some, so ignore them

    my @actions = @params{qw/action1 action2/};

    my $h = $self->sd->open_write_handle('foo.txt');
    $h->write("In foo.txt\n");
    $h->close(sub {
        my ( $ok, $error ) = @_;

        ok $ok or diag $error;
    });

    $_->() foreach @actions;
    $self->expect_changes($params{'changes'} || ['foo.txt']);
}

sub test_update_update_conflict :Tests(8) {
    my ( $self ) = @_;

    my $conflict_file;
    $self->perform_conflict_test(
        action1 => sub { append_file 'foo.txt', "Next line" },
        action2 => sub {
            my $h = $self->sd->open_write_handle('foo.txt');
            $h->write("Conflict!");
            $h->close(sub {
                my ( $ok, $error );
                ( $ok, $error, $conflict_file ) = @_;

                my $content = read_file('foo.txt');
                is $content, "In foo.txt\nNext line";
                ok $conflict_file;
                $content = read_file($conflict_file);
                is $content, "Conflict!";

                ok !$ok;
                like $error, qr/conflict/i;
            });
        },
    );

    ok ! -e $conflict_file;
}

sub test_update_delete_conflict :Test(6) {
    my ( $self ) = @_;

    $self->perform_conflict_test(
        action1 => sub { append_file 'foo.txt', "Next line" },
        action2 => sub { $self->sd->unlink('foo.txt', sub {
            my ( $ok, $error, $conflict_file ) = @_;

            my $contents = read_file('foo.txt');
            is $contents, "In foo.txt\nNext line";

            ok !$ok;
            like $error, qr/conflict/i;
            ok !defined($conflict_file);
        }) },
    );
}

sub test_update_rename_conflict :Test(7) {
    my ( $self ) = @_;

    $self->perform_conflict_test(
        action1 => sub { append_file 'foo.txt', "Next line" },
        action2 => sub {
            $self->sd->rename('foo.txt', 'bar.txt', sub {
                my ( $ok, $error, $conflict_file ) = @_;

                my $contents = read_file('foo.txt');
                is $contents, "In foo.txt\nNext line";

                ok ! -e 'bar.txt';

                ok !$ok;
                like $error, qr/conflict/i;
                ok !defined($conflict_file);
            });
        },
    );
}

sub test_delete_update_conflict :Test(8) {
    my ( $self ) = @_;

    my $conflict_file;
    $self->perform_conflict_test(
        action1 => sub { unlink 'foo.txt' },
        action2 => sub {
            my $h = $self->sd->open_write_handle('foo.txt');
            $h->write("Conflict!");
            $h->close(sub {
                my ( $ok, $error );
                ( $ok, $error, $conflict_file ) = @_;

                ok ! -e 'foo.txt';
                ok $conflict_file;
                my $content = read_file($conflict_file);
                is $content, "Conflict!";

                ok !$ok;
                like $error, qr/conflict/i;
            });
        },
    );

    ok ! -e $conflict_file;
}

sub test_delete_delete_conflict :Test(6) {
    my ( $self ) = @_;

    $self->perform_conflict_test(
        action1 => sub { unlink 'foo.txt' },
        action2 => sub {
            $self->sd->unlink('foo.txt', sub {
                my ( $ok, $error, $conflict_file ) = @_;

                ok ! -e 'foo.txt';
                ok !$ok;
                like $error, qr/conflict/i;
                ok !defined($conflict_file);
            });
        },
    );
}

sub test_delete_rename_conflict :Test(7) {
    my ( $self ) = @_;

    $self->perform_conflict_test(
        action1 => sub { unlink 'foo.txt' },
        action2 => sub {
            $self->sd->rename('foo.txt', 'bar.txt', sub {
                my ( $ok, $error, $conflict_file ) = @_;

                ok ! -e 'foo.txt';
                ok ! -e 'bar.txt';

                ok !$ok;
                like $error, qr/conflict/;
                ok !defined($conflict_file);
            });
        },
    );
}

sub test_rename_update :Test(9) {
    my ( $self ) = @_;

    my $conflict_file;
    $self->perform_conflict_test(
        action1 => sub { rename 'foo.txt', 'bar.txt' },
        action2 => sub {
            my $h = $self->sd->open_write_handle('foo.txt');
            $h->write('Conflict!');
            $h->close(sub {
                my ( $ok, $error );
                ( $ok, $error, $conflict_file ) = @_;

                ok ! -e 'foo.txt';
                my $content = read_file('bar.txt');
                is $content, "In foo.txt\n";

                ok $conflict_file;
                $content = read_file($conflict_file);
                is $content, 'Conflict!';

                ok !$ok;
                like $error, qr/conflict/i;
            });
        },
        changes => [qw/foo.txt bar.txt/],
    );

    ok ! -e $conflict_file;
}

sub test_rename_delete :Test(7) {
    my ( $self ) = @_;

    $self->perform_conflict_test(
        action1 => sub { rename 'foo.txt', 'bar.txt' },
        action2 => sub {
            $self->sd->unlink('foo.txt', sub {
                my ( $ok, $error, $conflict_file ) = @_;

                ok ! -e 'foo.txt';
                my $content = read_file('bar.txt');
                is $content, "In foo.txt\n";

                ok !defined($conflict_file);

                ok !$ok;
                like $error, qr/conflict/i;
            });
        },
        changes => [qw/foo.txt bar.txt/],
    );
}

sub test_rename_rename :Test(8) {
    my ( $self ) = @_;

    $self->perform_conflict_test(
        action1 => sub { rename 'foo.txt', 'bar.txt' },
        action2 => sub {
            $self->sd->rename('foo.txt', 'baz.txt', sub {
                my ( $ok, $error, $conflict_file ) = @_;

                ok ! -e 'foo.txt';
                ok ! -e 'baz.txt';
                my $content = read_file('bar.txt');
                is $content, "In foo.txt\n";

                ok !defined($conflict_file);

                ok !$ok;
                like $error, qr/conflict/i;
            });
        },
        changes => [qw/foo.txt bar.txt/],
    );
}

sub test_rename_existing_file :Test(1) {
}

sub test_rename_with_open_handle_same :Test(1) {
}

sub test_unlink_with_open_handle_same :Test(1) {
}

sub test_open_with_open_handle_same :Test(1) {
}

sub test_rename_with_open_handle_diff :Test(1) {
}

sub test_unlink_with_open_handle_diff :Test(1) {
}

sub test_open_with_open_handle_diff :Test(1) {
}

sub test_rename_in_conflict_handler :Test(1) {
}

my $tempdir = File::Temp->newdir;
my $sd      = SaharaSync::Clientd::SyncDir->create_syncdir(
    root => $tempdir->dirname,
);

if(defined $sd) {
    __PACKAGE__->runtests;
} else {
    plan skip_all => 'No sync dir implemention exists for this OS';
}
