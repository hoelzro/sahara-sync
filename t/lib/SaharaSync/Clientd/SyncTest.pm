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
use Test::Sahara::Proxy;
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
    my ( $self, $sync_dir, $client_num, %opts ) = @_;

    confess "client num required" unless $client_num;

    my @client_info = grep { /^client$client_num/} keys %$self;
    if(@client_info) {
        confess "create_fresh_client called with the following client info keys: "
            . join(' ', @client_info);
    }

    my ( $read, $write );

    pipe $read, $write;

    my $upstream_port = exists $opts{'proxy'} ? $opts{'proxy'}->port : $self->port;

    # this is easier than managing the client process ourselves
    my $client = Test::TCP->new(
        code => sub {
            my ( $port ) = @_;

            close $read;

            dup2 fileno($write), 3 or die $!;
            close $write;

            $ENV{'_CLIENTD_PORT'}          = $port;
            $ENV{'_CLIENTD_UPSTREAM'}      = 'http://localhost:' . $upstream_port;
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

sub create_fresh_host {
    my ( $self, %opts ) = @_;

    if($self->{'hostd'} || $self->{'hostd_pipe'}) {
        confess "create_fresh_host called without checking the host first";
    }

    my ( $read, $write );

    pipe $read, $write;
    my $hostd = Test::TCP->new(
        $opts{'port'} ? ( port => $opts{'port'} ) : (),

        code => sub {
            my ( $port ) = @_;

            close $read;
            dup2 fileno($write), 3 or die $!;
            close $write;

            $ENV{'_HOSTD_PORT'} = $port;

            exec $^X, 't/run-test-app';
        },
    );

    close $write;
    my $pipe = IO::Handle->new;
    $pipe->fdopen(fileno($read), 'r');
    close $read;

    $pipe->blocking(0);

    return ( $hostd, $pipe );
}

sub get_conflict_blob {
    my ( $self, $blob ) = @_;

    my ( $day, $month, $year ) = (localtime)[3, 4, 5];
    $year += 1900;
    $month++;

    return sprintf("%s - conflict %04d-%02d-%02d", $blob, $year, $month, $day);
}

# This is two tests in one method
# It also cleans up the client pipe and object
sub check_client {
    my ( $self, $client_num ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    delete $self->{'client' . $client_num};
    my $pipe   = delete $self->{'client' . $client_num . '_pipe'};
    my $buffer = '';
    my $bytes  = $pipe->sysread($buffer, 1);
    $pipe->close;

    my $ok = 1;
    $ok = is($bytes, 1, 'The client should write a status byte upon safe exit') && $ok;
    $ok = is($buffer, 0, 'No errors should occur in the client')                && $ok;

    return $ok;
}

# four tests in one
# XXX consider rename
sub check_clients {
    my ( $self ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $ok = $self->check_client(1);
       $ok = $self->check_client(2) && $ok;

    unless($ok) {
        diag("Client check in method " . $self->current_method . " failed");
    }
}

# This method runs two tests, and cleans up the host object/pipe
sub check_host {
    my ( $self ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    delete $self->{'hostd'};

    my $pipe   = delete $self->{'hostd_pipe'};
    my $buffer = '';
    my $bytes  = $pipe->sysread($buffer, 1);
    $pipe->close;

    my $ok = 1;

    $ok = is($bytes, 1, 'The host should write a status byte upon safe exit') && $ok;
    $ok = is($buffer, 0, 'No errors should occur in the host') && $ok;

    unless($ok) {
        diag("Host check in method " . $self->current_method . " failed");
    }
}

sub check_files {
    my ( $self, %opts ) = @_;

    # $opts{'force_wait'}

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $client_no  = $opts{'client'};
    my $files      = $opts{'files'};
    my $name       = $opts{'name'};
    my $wait_time  = $opts{'wait_time'};
    my $is_waiting = exists($opts{'wait'}) ? $opts{'wait'} : 1;

    # XXX check %opts

    if($is_waiting) {
        $self->catchup($wait_time); # wait for a sync period
    }

    my $temp_dir = $self->{'temp' . $client_no};

    # this bit might be a little too specific to the inotify implementation...
    my @files         = grep { $_ ne '.saharasync' } read_dir($temp_dir);
    my %file_contents = (
        map {
            $_ => read_file(File::Spec->catfile($temp_dir, $_))
        } @files
    );

    is_deeply \%file_contents, $files, $name;
}

sub setup : Test(setup) {
    my ( $self ) = @_;

    $self->port(undef);

    @{$self}{qw/hostd hostd_pipe/} = $self->create_fresh_host;

    $self->port($self->{'hostd'}->port);

    my $temp1 = File::Temp->newdir;
    my $temp2 = File::Temp->newdir;

    @{$self}{qw/client1 client1_pipe/} = $self->create_fresh_client($temp1, 1);
    @{$self}{qw/client2 client2_pipe/} = $self->create_fresh_client($temp2, 2);
    $self->{'temp1'}   = $temp1;
    $self->{'temp2'}   = $temp2;
}

sub teardown : Test(teardown => 6) {
    my ( $self ) = @_;

    $self->check_clients; # stop client daemons first (4 tests)
    $self->check_host;    # stop host daemon (1 test)

    delete @{$self}{qw/temp1 temp2/};
}

sub test_create_file :Test(1) {
    my ( $self ) = @_;

    my $temp1 = $self->{'temp1'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello!\n");

    $self->check_files(
        client => 2,
        files  => {
            'foo.txt' => "Hello!\n",
        },
    );
}

sub test_delete_file :Test(2) {
    my ( $self ) = @_;

    my $temp1 = $self->{'temp1'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello!\n");

    $self->check_files(
        client => 2,
        files  => {
            'foo.txt' => "Hello!\n",
        },
    );

    unlink File::Spec->catfile($temp1, 'foo.txt');

    $self->check_files(
        client => 2,
        files  => {},
    );
}

sub test_update_file :Test(2) {
    my ( $self ) = @_;

    my $temp1  = $self->{'temp1'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello!\n");

    $self->check_files(
        client => 2,
        files  => {
            'foo.txt' => "Hello!\n",
        },
    );

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello 2\n");

    $self->check_files(
        client => 2,
        files  => {
            'foo.txt' => "Hello 2\n",
        },
    );
}

sub test_preexisting_files :Test(6) {
    my ( $self ) = @_;

    my $temp1  = $self->{'temp1'};
    my $temp2  = $self->{'temp2'};

    $self->check_clients;

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello, World!");

    $self->check_files(
        client => 2,
        files  => {},
    );
    @{$self}{qw/client1 client1_pipe/} = $self->create_fresh_client($temp1, 1);
    @{$self}{qw/client2 client2_pipe/} = $self->create_fresh_client($temp2, 2);

    $self->check_files(
        client => 2,
        files  => {
            'foo.txt' => 'Hello, World!',
        },
    );
}

sub test_offline_update :Test(7) {
    my ( $self ) = @_;

    my $temp1  = $self->{'temp1'};
    my $temp2  = $self->{'temp2'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello, World!");

    $self->check_files(
        client => 2,
        files  => {
            'foo.txt' => 'Hello, World!',
        },
    );

    $self->check_clients;

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello, again");

    $self->check_files(
        client     => 2,
        force_wait => 1,
        files  => {
            'foo.txt' => 'Hello, World!',
        },
    );

    @{$self}{qw/client1 client1_pipe/} = $self->create_fresh_client($temp1, 1);
    @{$self}{qw/client2 client2_pipe/} = $self->create_fresh_client($temp2, 2);

    $self->check_files(
        client     => 2,
        force_wait => 1,
        files  => {
            'foo.txt' => 'Hello, again',
        },
    );
}

sub test_revision_persistence :Test(7) {
    my ( $self ) = @_;

    my $temp1  = $self->{'temp1'};
    my $temp2  = $self->{'temp2'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello, World!");

    $self->check_files(
        client => 2,
        files  => {
            'foo.txt' => 'Hello, World!',
        },
    );

    $self->check_clients;
    @{$self}{qw/client1 client1_pipe/} = $self->create_fresh_client($temp1, 1);
    @{$self}{qw/client2 client2_pipe/} = $self->create_fresh_client($temp2, 2);

    $self->check_files(
        client => 2,
        files  => {
            'foo.txt' => 'Hello, World!',
        },
    );

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Hello, again");

    $self->check_files(
        client => 2,
        files  => {
            'foo.txt' => 'Hello, again',
        },
    );
}

sub test_update_on_nonorigin :Test(2) {
    my ( $self ) = @_;

    my $temp1 = $self->{'temp1'};
    my $temp2 = $self->{'temp2'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "In foo");

    $self->check_files(
        client => 2,
        files  => {
            'foo.txt' => 'In foo',
        },
    );

    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Second update to foo");

    $self->check_files(
        client => 1,
        files  => {
            'foo.txt' => 'Second update to foo',
        },
    );
}

sub test_create_conflict :Test(3) {
    my ( $self ) = @_;

    my $client1 = $self->{'client1'};
    my $client2 = $self->{'client2'};
    my $temp1   = $self->{'temp1'};
    my $temp2   = $self->{'temp2'};

    kill SIGSTOP => $client1->pid;

    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Content 2\n");
    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Content 1\n");

    $self->check_files(
        client => 1,
        files  => {
            'foo.txt' => "Content 1\n",
        },
    );

    kill SIGCONT => $client1->pid;

    my $conflict_file = $self->get_conflict_blob('foo.txt');

    $self->check_files(
        client    => 1,
        wait_time => 5,
        files     => {
            $conflict_file => "Content 1\n",
            'foo.txt'      => "Content 2\n",
        },
    );

    $self->check_files(
        client => 2,
        wait   => 0,
        files  => {
            $conflict_file => "Content 1\n",
            'foo.txt'      => "Content 2\n",
        },
    );
}

sub test_update_conflict :Test(2) {
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

    my $conflict_file = $self->get_conflict_blob('foo.txt');

    $self->check_files(
        client => 2,
        files  => {
            'foo.txt'      => 'Updated content',
            $conflict_file => 'Conflicting content!',
        },
    );

    $self->check_files(
        client => 1,
        wait   => 0,
        files  => {
            'foo.txt'      => 'Updated content',
            $conflict_file => 'Conflicting content!',
        },
    );
}

sub test_delete_update_conflict :Test(2) {
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

    my $conflict_file = $self->get_conflict_blob('foo.txt');
    $self->check_files(
        client    => 1,
        wait_time => 5,
        files     => {
            $conflict_file => 'Updated content',
        },
    );

    $self->check_files(
        client    => 2,
        wait      => 0,
        files     => {
            $conflict_file => 'Updated content',
        },
    );
}

sub test_update_delete_conflict :Test(2) {
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

    $self->check_files(
        client    => 1,
        wait_time => 5,
        files     => {
            'foo.txt' => 'Updated content',
        },
    );

    $self->check_files(
        client    => 2,
        wait      => 0,
        files     => {
            'foo.txt' => 'Updated content',
        },
    );
}

# shuts down client 2 and re-establishes it to talk through a proxy
sub setup_proxied_client {
    my ( $self ) = @_;

    $self->catchup; # wait for child to establish signal handlers

    $self->check_client(2);

    my $proxy = Test::Sahara::Proxy->new(remote => $self->port);

    @{$self}{qw/client2 client2_pipe/} = $self->create_fresh_client($self->{'temp2'}, 2,
        proxy => $proxy,
    );

    $self->catchup; # let client 2 get situated

    return $proxy;
}

# restarts the given client
# XXX we should probably preserve whether or not the client goes through a proxy
sub restart_client {
    my ( $self, $client_num ) = @_;

    $self->check_client(2);

    @{$self}{qw/client2 client2_pipe/} = $self->create_fresh_client($self->{'temp2'}, 2);

    $self->catchup; # let the new client get situated
}

sub test_hostd_unavailable_after_change :Test(5) {
    my ( $self ) = @_;

    my $temp1 = $self->{'temp1'};
    my $temp2 = $self->{'temp2'};

    my $proxy   = $self->setup_proxied_client;
    my $client1 = $self->{'client1'};
    my $client2 = $self->{'client2'};

    $proxy->kill_connections;

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Content\n");
    
    $self->catchup; # let the changes sync up

    $proxy->resume_connections;

    $self->check_files(
        name   => 'changes should be synced even when the link goes down',
        client => 2,
        files  => {
            'foo.txt' => "Content\n",
        },
    );
}

sub test_hostd_unavailable_at_start :Test(5) {
    my ( $self ) = @_;

    my $temp1 = $self->{'temp1'};
    my $temp2 = $self->{'temp2'};

    $self->catchup; # wait for the child to establish signal handlers

    $self->check_client(2);

    my $proxy = Test::Sahara::Proxy->new(remote => $self->port);
    $proxy->kill_connections;

    @{$self}{qw/client2 client2_pipe/} = $self->create_fresh_client($temp2, 2,
        proxy => $proxy,
    );
    my $client1 = $self->{'client1'};
    my $client2 = $self->{'client2'};

    $self->catchup; # let client 2 get situated

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Content\n");
    
    $self->catchup; # let the changes sync up

    $proxy->resume_connections;

    $self->check_files(
        name   => 'changes should be synced even when the link starts down',
        client => 2,
        files  => {
            'foo.txt' => "Content\n",
        }
    );
}

sub test_hostd_unavailable_last_sync :Test(5) {
    my ( $self ) = @_;

    my $temp1 = $self->{'temp1'};
    my $temp2 = $self->{'temp2'};

    my $proxy = $self->setup_proxied_client;

    my $client1 = $self->{'client1'};
    my $client2 = $self->{'client2'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Content\n");
    
    $self->catchup; # let the changes sync up

    $proxy->kill_connections;

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Updated content\n");
    
    $self->catchup; # let the changes sync up

    $proxy->resume_connections;

    $self->check_files(
        name   => 'changes should be synced even when the link goes down',
        client => 2,
        files  => {
            'foo.txt' => "Updated content\n",
        },
    );
}

sub test_hostd_unavailable_get_blob :Test(5) {
    my ( $self ) = @_;

    my $temp1 = $self->{'temp1'};
    my $temp2 = $self->{'temp2'};

    my $proxy = $self->setup_proxied_client;

    my $client1 = $self->{'client1'};
    my $client2 = $self->{'client2'};

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Content\n");

    $self->catchup;

    $proxy->kill_connections(preserve_existing => 1);

    write_file(File::Spec->catfile($temp1, 'foo.txt'), "Updated Content\n");

    $self->catchup;

    $proxy->resume_connections;

    $self->check_files(
        name   => 'changes should be synced even when the link goes down',
        client => 2,
        files  => {
            'foo.txt' => "Updated Content\n",
        },
    );
}

sub test_put_blob_client_error :Test {
    my ( $self ) = @_;

    return 'Test not implemented';
}

sub test_put_blob_bad_perms :Test {
    my ( $self ) = @_;

    return 'Test not implemented';
}

sub test_put_blob_host_error :Test(3) {
    my ( $self ) = @_;

    my $temp1 = $self->{'temp1'};
    my $temp2 = $self->{'temp2'};
    my $proxy = $self->setup_proxied_client;

    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Content\n");

    $self->catchup;

    $proxy->kill_connections(preserve_existing => 1);

    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Updated Content\n");

    $self->catchup;

    $proxy->resume_connections;

    $self->check_files(
        name   => 'changes should be synced even when the link goes down',
        client => 1,
        files  => {
            'foo.txt' => "Updated Content\n",
        },
    );
}

sub test_put_blob_host_error_offline :Test(5) {
    my ( $self ) = @_;

    my $temp1 = $self->{'temp1'};
    my $temp2 = $self->{'temp2'};
    my $proxy = $self->setup_proxied_client;

    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Content\n");

    $self->catchup;

    $proxy->kill_connections(preserve_existing => 1);

    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Updated Content\n");

    $self->catchup;

    $self->restart_client(2);

    $proxy->resume_connections;

    $self->check_files(
        name   => 'changes should be synced even when the link goes down',
        client => 1,
        files  => {
            'foo.txt' => "Updated Content\n",
        },
    ); # XXX retry time?
}

sub test_put_blob_bad_perms_offline :Test {
    my ( $self ) = @_;

    return 'Test not implemented';
}

sub test_delete_blob_client_error :Test {
    my ( $self ) = @_;

    return 'Test not implemented';
}

sub test_delete_blob_bad_perms :Test {
    my ( $self ) = @_;

    return 'Test not implemented';
}

sub test_delete_blob_host_error :Test(3) {
    my ( $self ) = @_;

    my $temp1 = $self->{'temp1'};
    my $temp2 = $self->{'temp2'};
    my $proxy = $self->setup_proxied_client;

    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Content\n");

    $self->catchup;

    $proxy->kill_connections(preserve_existing => 1);

    unlink(File::Spec->catfile($temp2, 'foo.txt'));

    $self->catchup;

    $proxy->resume_connections;

    $self->check_files(
        client => 1,
        files  => {},
    );
}

sub test_delete_blob_host_error_offline :Test(5) {
    my ( $self ) = @_;

    my $temp1 = $self->{'temp1'};
    my $temp2 = $self->{'temp2'};
    my $proxy = $self->setup_proxied_client;

    write_file(File::Spec->catfile($temp2, 'foo.txt'), "Content\n");

    $self->catchup;

    $proxy->kill_connections(preserve_existing => 1);

    unlink(File::Spec->catfile($temp2, 'foo.txt'));

    $self->catchup;

    $self->restart_client(2);

    $proxy->resume_connections;

    $self->check_files(
        client => 1,
        files  => {},
    ); # XXX retry time?
}

sub test_delete_blob_bad_perms_offline :Test {
    my ( $self ) = @_;

    return 'Test not implemented';
}

__PACKAGE__->SKIP_CLASS(1);

# XXX metadata + sync test (when we actually start providing metadata)

1;
