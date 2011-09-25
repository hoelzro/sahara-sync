package SaharaSync::Clientd::SyncTest;

use strict;
use warnings;
use autodie qw(open pipe);
use parent 'Test::Class::AnyEvent';

use IO::Handle;
use File::Slurp qw(read_dir read_file write_file);
use File::Spec;
use File::Temp;
use Test::Deep qw(cmp_bag);
use Test::More;
use Test::Sahara ();
use Test::TCP;
use Try::Tiny;

sub client_poll_interval {
    return 1;
}

sub catchup {
    my ( $self, $extra ) = @_;

    $extra = 1 unless defined $extra;

    for(my $i = 0; $i < $self->client_poll_interval + $extra; $i++) {
        sleep 1;
    }
}

sub port {
    return Test::Sahara->port;
}

sub create_fresh_client {
    my ( $self, $sync_dir ) = @_;

    my ( $read, $write );

    pipe $read, $write;

    # this is easier than managing the client process ourselves
    my $client = Test::TCP->new(
        code => sub {
            my ( $port ) = @_;

            close $read;

            open STDOUT, '>&', $write;

            exec $^X, 't/run-test-client', 'http://localhost:' . $self->port,
                $port, $sync_dir->dirname, $self->client_poll_interval;
        },
    );

    close $write;
    my $pipe = IO::Handle->new;
    $pipe->fdopen(fileno($read), 'r');
    close $read;

    return ( $client, $pipe );
}

sub get_conflict_blob {
    my ( $self, $blob ) = @_;

    my ( $day, $month, $year ) = (localtime)[3, 4, 5];
    $year += 1900;
    $month++;

    return sprintf("%s - conflict %04d-%02d-%02d", $blob, $year, $month, $day);
}

sub setup : Test(setup) {
    my ( $self ) = @_;

    $self->{'hostd'} = Test::TCP->new(
        port => $self->port,
        code => sub {
            exec $^X, 't/run-test-app', @_;
        },
    );

    my $temp1 = File::Temp->newdir;
    my $temp2 = File::Temp->newdir;

    ( $self->{'client1'} ) = $self->create_fresh_client($temp1);
    ( $self->{'client2'} ) = $self->create_fresh_client($temp2);
    $self->{'temp1'}   = $temp1;
    $self->{'temp2'}   = $temp2;
}

sub teardown : Test(teardown) {
    my ( $self ) = @_;

    delete @{$self}{qw/client1 client2/}; # stop client daemons first
    delete $self->{'hostd'};
    delete @{$self}{qw/temp1 temp2/};
}

sub test_create_file :Test(5) {
    my ( $self ) = @_;

    my $temp1  = $self->{'temp1'};
    my $temp2  = $self->{'temp2'};
    # this bit might be a little too specific to the inotify implementation...
    my @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    my @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);

    is_deeply(\@files1, []);
    is_deeply(\@files2, []);

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello!\n");

    $self->catchup;

    @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);
    is_deeply(\@files1, ['foo.txt']);
    is_deeply(\@files2, ['foo.txt']);

    my $contents = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $contents, "Hello!\n";
}

sub test_delete_file :Test(7) {
    my ( $self ) = @_;

    my $temp1  = $self->{'temp1'};
    my $temp2  = $self->{'temp2'};
    # this bit might be a little too specific to the inotify implementation...
    my @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    my @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);

    is_deeply(\@files1, []);
    is_deeply(\@files2, []);

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello!\n");

    $self->catchup;

    @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);
    is_deeply(\@files1, ['foo.txt']);
    is_deeply(\@files2, ['foo.txt']);

    my $contents = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $contents, "Hello!\n";

    unlink File::Spec->catfile($temp1, 'foo.txt');

    $self->catchup;

    @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);

    is_deeply(\@files1, []);
    is_deeply(\@files2, []);
}

sub test_update_file :Test(8) {
    my ( $self ) = @_;

    my $temp1  = $self->{'temp1'};
    my $temp2  = $self->{'temp2'};
    # this bit might be a little too specific to the inotify implementation...
    my @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    my @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);

    is_deeply(\@files1, []);
    is_deeply(\@files2, []);

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello!\n");

    $self->catchup;

    @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);
    is_deeply(\@files1, ['foo.txt']);
    is_deeply(\@files2, ['foo.txt']);

    my $contents = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $contents, "Hello!\n";

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello 2\n");

    $self->catchup;

    @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);

    is_deeply(\@files1, ['foo.txt']);
    is_deeply(\@files2, ['foo.txt']);

    $contents = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is($contents, "Hello 2\n");
}

sub test_preexisting_files :Test(5) {
    my ( $self ) = @_;

    my $temp1  = $self->{'temp1'};
    my $temp2  = $self->{'temp2'};

    $self->{'client1'} = $self->{'client2'} = undef;

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello, World!");

    $self->catchup;

    my @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    my @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);

    is_deeply(\@files1, ['foo.txt']);
    is_deeply(\@files2, []);

    ( $self->{'client1'} ) = $self->create_fresh_client($temp1);
    ( $self->{'client2'} ) = $self->create_fresh_client($temp2);

    $self->catchup;

    @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);

    is_deeply(\@files1, ['foo.txt']);
    is_deeply(\@files2, ['foo.txt']);

    my $content = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $content, "Hello, World!";
}

sub test_offline_update :Test(4) {
    my ( $self ) = @_;

    my $temp1  = $self->{'temp1'};
    my $temp2  = $self->{'temp2'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello, World!");

    $self->catchup;

    my @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    my @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);

    is_deeply(\@files1, ['foo.txt']);
    is_deeply(\@files2, ['foo.txt']);

    $self->{'client1'} = $self->{'client2'} = undef;

    $self->catchup;

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello, again");

    $self->catchup;

    my $content = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $content, "Hello, World!";

    ( $self->{'client1'} ) = $self->create_fresh_client($temp1);
    ( $self->{'client2'} ) = $self->create_fresh_client($temp2);

    $self->catchup;

    $content = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $content, "Hello, again";
}

sub test_revision_persistence :Test(4) {
    my ( $self ) = @_;

    my $temp1  = $self->{'temp1'};
    my $temp2  = $self->{'temp2'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello, World!");

    $self->catchup;

    my @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    my @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);

    is_deeply(\@files1, ['foo.txt']);
    is_deeply(\@files2, ['foo.txt']);

    $self->{'client1'} = undef;
    $self->{'client2'} = undef;

    $self->catchup;

    ( $self->{'client1'} ) = $self->create_fresh_client($temp1);
    ( $self->{'client2'} ) = $self->create_fresh_client($temp2);

    $self->catchup;

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello, again");

    my $content = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $content, "Hello, World!";

    $self->catchup;

    $content = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $content, "Hello, again";
}

sub test_update_on_nonorigin :Test(2) {
    my ( $self ) = @_;

    my $temp1 = $self->{'temp1'};
    my $temp2 = $self->{'temp2'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "In foo");

    $self->catchup;

    my $content = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');

    is $content, "In foo";

    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Second update to foo");

    $self->catchup;

    $content = read_file(File::Spec->catfile($temp1, 'foo.txt'), err_mode => 'quiet');

    is $content, "Second update to foo";
}

sub test_create_conflict :Test(7) {
    my ( $self ) = @_;

    my $client1 = $self->{'client1'};
    my $client2 = $self->{'client2'};
    my $temp1   = $self->{'temp1'};
    my $temp2   = $self->{'temp2'};

    kill SIGSTOP => $client1->pid;

    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Content 2\n");
    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Content 1\n");

    $self->catchup;

    my @files = grep { $_ ne '.saharasync' } read_dir $temp1;
    is_deeply \@files, ['foo.txt'];

    kill SIGCONT => $client1->pid;

    $self->catchup(5); # wait a little longer

    @files = grep { $_ ne '.saharasync' } read_dir $temp1;

    my $conflict_file = $self->get_conflict_blob('foo.txt');
    cmp_bag \@files, [ 'foo.txt', $conflict_file ];

    my $content = read_file(File::Spec->catfile($temp1, 'foo.txt'), err_mode => 'quiet');
    is $content, "Content 2\n";

    $content = read_file(File::Spec->catfile($temp1, $conflict_file), err_mode => 'quiet');
    is $content, "Content 1\n";

    @files = grep { $_ ne '.saharasync' } read_dir($temp2);

    cmp_bag \@files, [ 'foo.txt', $conflict_file ];

    $content = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $content, "Content 2\n";

    $content = read_file(File::Spec->catfile($temp2, $conflict_file), err_mode => 'quiet');
    is $content, "Content 1\n";
}

sub test_update_conflict :Test(6) {
    my ( $self ) = @_;

    my $client1 = $self->{'client1'};
    my $client2 = $self->{'client2'};
    my $temp1   = $self->{'temp1'};
    my $temp2   = $self->{'temp2'};

    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Test content");

    $self->catchup;

    kill SIGSTOP => $client2->pid;

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Updated content");
    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Conflicting content!");

    $self->catchup;

    kill SIGCONT => $client2->pid;

    $self->catchup;

    my $conflict_file = $self->get_conflict_blob('foo.txt');
    my @files = grep { $_ ne '.saharasync' } read_dir $temp2;

    cmp_bag \@files, [ 'foo.txt', $conflict_file ];

    my $content = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $content, "Updated content";

    $content = read_file(File::Spec->catfile($temp2, $conflict_file), err_mode => 'quiet');
    is $content, "Conflicting content!";

    @files = grep { $_ ne '.saharasync' } read_dir $temp1;

    cmp_bag \@files, [ 'foo.txt', $conflict_file ];

    $content = read_file(File::Spec->catfile($temp1, 'foo.txt'), err_mode => 'quiet');
    is $content, "Updated content";

    $content = read_file(File::Spec->catfile($temp1, $conflict_file), err_mode => 'quiet');
    is $content, "Conflicting content!";
}

sub test_update_delete_conflict :Test(4) {
    my ( $self ) = @_;

    my $client1 = $self->{'client1'};
    my $client2 = $self->{'client2'};
    my $temp1   = $self->{'temp1'};
    my $temp2   = $self->{'temp2'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Test content");

    $self->catchup;

    kill SIGSTOP => $client1->pid;

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Updated content");
    unlink File::Spec->catfile($temp2, 'foo.txt');

    $self->catchup;

    kill SIGCONT => $client1->pid;

    $self->catchup(5);

    my $conflict_file = $self->get_conflict_blob('foo.txt');
    my @files = grep { $_ ne '.saharasync' } read_dir $temp1;

    is_deeply \@files, [ $conflict_file ];

    my $content = read_file(File::Spec->catfile($temp1, $conflict_file), err_mode => 'quiet');
    is $content, "Updated content";

    @files = grep { $_ ne '.saharasync' } read_dir $temp2;

    is_deeply \@files, [ $conflict_file ];

    $content = read_file(File::Spec->catfile($temp2, $conflict_file), err_mode => 'quiet');
    is $content, "Updated content";
}

sub test_delete_update_conflict :Test(4) {
    my ( $self ) = @_;

    my $client1 = $self->{'client1'};
    my $client2 = $self->{'client2'};
    my $temp1   = $self->{'temp1'};
    my $temp2   = $self->{'temp2'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Test content");

    $self->catchup;

    kill SIGSTOP => $client1->pid;

    unlink File::Spec->catfile($temp1, 'foo.txt');
    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Updated content");

    $self->catchup;

    kill SIGCONT => $client1->pid;

    $self->catchup(5);

    my ( $day, $month, $year ) = (localtime)[3, 4, 5];
    $month++;
    $year += 1900;

    my @files = grep { $_ ne '.saharasync' } read_dir $temp1;

    is_deeply \@files, [ 'foo.txt' ];

    my $content = read_file(File::Spec->catfile($temp1, 'foo.txt'), err_mode => 'quiet');
    is $content, "Updated content";

    @files = grep { $_ ne '.saharasync' } read_dir $temp2;

    is_deeply \@files, [ 'foo.txt' ];

    $content = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $content, "Updated content";
}

1;
