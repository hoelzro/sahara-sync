package SaharaSync::Clientd::SyncTest;

use strict;
use warnings;
use autodie qw(open pipe);
use parent 'Test::Class::AnyEvent';

use Carp qw(confess);
use IO::Handle;
use File::Slurp qw(read_dir read_file write_file);
use File::Spec;
use File::Temp;
use POSIX qw(dup2);
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
    my $self = shift;

    if(@_) {
        $self->{'port'} = shift;
    }

    return $self->{'port'};
}

sub create_fresh_client {
    my ( $self, $sync_dir, $client_num ) = @_;

    confess "client num required" unless $client_num;

    my @client_info = grep { /^client$client_num/} keys %$self;
    if(@client_info) {
        confess "create_fresh_client called with the following client info keys: "
            . join(' ', @client_info);
    }

    my ( $read, $write );

    pipe $read, $write;

    # this is easier than managing the client process ourselves
    my $client = Test::TCP->new(
        code => sub {
            my ( $port ) = @_;

            close $read;

            dup2 fileno($write), 3 or die $!;
            close $write;

            $ENV{'_CLIENTD_PORT'}          = $port;
            $ENV{'_CLIENTD_UPSTREAM'}      = 'http://localhost:' . $self->port;
            $ENV{'_CLIENTD_ROOT'}          = $sync_dir->dirname;
            $ENV{'_CLIENTD_POLL_INTERVAL'} = $self->client_poll_interval;
            $ENV{'_CLIENTD_NUM'}           = $client_num;

            exec $^X, 't/run-test-client';
        },
    );

    close $write;
    my $pipe = IO::Handle->new;
    $pipe->fdopen(fileno($read), 'r');
    close $read;

    $pipe->blocking(0);

    return ( $client, $pipe );
}

sub get_conflict_blob {
    my ( $self, $blob ) = @_;

    my ( $day, $month, $year ) = (localtime)[3, 4, 5];
    $year += 1900;
    $month++;

    return sprintf("%s - conflict %04d-%02d-%02d", $blob, $year, $month, $day);
}

# This is four tests in a single method
# It also cleans up the client pipes and the client objects
sub check_clients {
    my ( $self ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    delete @{$self}{qw/client1 client2/};

    my $ok = 1;

    foreach my $pipe (delete @{$self}{qw/client1_pipe client2_pipe/}) {
        my $buffer = '';
        my $bytes  = $pipe->sysread($buffer, 1);
        $pipe->close;
        $ok = is($bytes, 1, 'The client should write a status byte upon safe exit') && $ok;
        $ok = is($buffer, 0, 'No errors should occur in the clients')               && $ok;
    }
    unless($ok) {
        diag("Client check in method " . $self->current_method . " failed");
    }
}

sub setup : Test(setup) {
    my ( $self ) = @_;

    my ( $read, $write );

    $self->port(undef);

    pipe $read, $write;
    $self->{'hostd'} = Test::TCP->new(
        code => sub {
            my ( $port ) = @_;

            close $read;
            dup2 fileno($write), 3 or die $!;
            close $write;

            $ENV{'_HOSTD_PORT'} = $port;

            exec $^X, 't/run-test-app';
        },
    );
    $self->port($self->{'hostd'}->port);

    close $write;
    my $pipe = IO::Handle->new;
    $pipe->fdopen(fileno($read), 'r');
    close $read;

    $pipe->blocking(0);

    $self->{'hostd_pipe'} = $pipe;

    my $temp1 = File::Temp->newdir;
    my $temp2 = File::Temp->newdir;

    @{$self}{qw/client1 client1_pipe/} = $self->create_fresh_client($temp1, 1);
    @{$self}{qw/client2 client2_pipe/} = $self->create_fresh_client($temp2, 2);
    $self->{'temp1'}   = $temp1;
    $self->{'temp2'}   = $temp2;
}

sub teardown : Test(teardown => 5) {
    my ( $self ) = @_;

    $self->check_clients; # stop client daemons first (4 tests)
    delete $self->{'hostd'};
    delete @{$self}{qw/temp1 temp2/};
    my $pipe   = delete $self->{'hostd_pipe'};
    my $buffer = '';
    my $bytes  = $pipe->sysread($buffer, 1);
    $pipe->close;

    if($bytes == 1) {
        is $buffer, 0, 'No errors should occur in the host';
    } else {
        fail 'The host should write a status byte upon safe exit';
    }
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

sub test_preexisting_files :Test(9) {
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

    $self->check_clients;
    @{$self}{qw/client1 client1_pipe/} = $self->create_fresh_client($temp1, 1);
    @{$self}{qw/client2 client2_pipe/} = $self->create_fresh_client($temp2, 2);

    $self->catchup;

    @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);

    is_deeply(\@files1, ['foo.txt']);
    is_deeply(\@files2, ['foo.txt']);

    my $content = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $content, "Hello, World!";
}

sub test_offline_update :Test(8) {
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

    $self->check_clients;
    @{$self}{qw/client1 client1_pipe/} = $self->create_fresh_client($temp1, 1);
    @{$self}{qw/client2 client2_pipe/} = $self->create_fresh_client($temp2, 2);

    $self->catchup;

    $content = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $content, "Hello, again";
}

sub test_revision_persistence :Test(8) {
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

    $self->check_clients;
    @{$self}{qw/client1 client1_pipe/} = $self->create_fresh_client($temp1, 1);
    @{$self}{qw/client2 client2_pipe/} = $self->create_fresh_client($temp2, 2);

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

sub test_delete_update_conflict :Test(4) {
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

sub test_update_delete_conflict :Test(4) {
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

    my $conflict_file = $self->get_conflict_blob('foo.txt');
    is_deeply \@files, [ 'foo.txt' ];

    my $content = read_file(File::Spec->catfile($temp1, 'foo.txt'), err_mode => 'quiet');
    is $content, "Updated content";

    @files = grep { $_ ne '.saharasync' } read_dir $temp2;

    is_deeply \@files, [ 'foo.txt' ];

    $content = read_file(File::Spec->catfile($temp2, 'foo.txt'), err_mode => 'quiet');
    is $content, "Updated content";
}

1;
