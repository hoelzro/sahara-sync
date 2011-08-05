use strict;
use warnings;
use autodie qw(open);
use parent 'Test::Class';

use AnyEvent::Socket qw(tcp_server);
use File::Slurp qw(read_dir read_file);
use File::Spec;
use File::Temp;
use SaharaSync::Clientd;
use SaharaSync::Clientd::Config;
use Plack::Loader;
use Test::More;
use Test::Sahara ();
use Test::TCP;
use Try::Tiny;

sub catchup {
    sleep 2;
}

sub port {
    return Test::Sahara->port;
}

sub create_fresh_client {
    my ( $self, $sync_dir ) = @_;

    my $log_config = {
        type => 'Null',
    };

    if($ENV{'TEST_CLIENTD_DEBUG'}) {
        $log_config = {
            type    => 'Screen',
            newline => 1,
            stderr  => 1,
        };
    }
    $log_config->{'min_level'} = 'debug';

    my $config = SaharaSync::Clientd::Config->new(
        upstream => 'http://localhost:' . $self->port,
        sync_dir => $sync_dir->dirname,
        username => 'test',
        password => 'abc123',
        log      => $log_config,
    );

    # this is easier than managing the client process ourselves
    return Test::TCP->new(
        code => sub {
            my ( $port ) = @_;

            # make sure Test::TCP can talk to us
            tcp_server '127.0.0.1', $port, sub {
                my ( $fh ) = @_;

                close $fh;
            };

            my $daemon = SaharaSync::Clientd->new($config);

            try {
                $daemon->run;
            } catch {
                fail "ERROR: $_";
            }
        },
    );
}

sub setup : Test(setup) {
    my ( $self ) = @_;

    $self->{'hostd'} = Test::TCP->new(
        port => $self->port,
        code => sub {
            my ( $port ) = @_;

            my $server = Plack::Loader->auto(
                port => $port,
                host => '127.0.0.1',
            );
            $server->run(Test::Sahara->create_fresh_app);
        },
    );

    my $temp1 = File::Temp->newdir;
    my $temp2 = File::Temp->newdir;

    $self->{'client1'} = $self->create_fresh_client($temp1);
    $self->{'client2'} = $self->create_fresh_client($temp2);
    $self->{'temp1'}   = $temp1;
    $self->{'temp2'}   = $temp2;
}

sub teardown : Test(teardown) {
    my ( $self ) = @_;

    delete @{$self}{qw/hostd client1 client2/};
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

    my $fh;

    open $fh, '>', File::Spec->catfile($temp1, 'foo.txt');
    print $fh "Hello!\n";
    close $fh;

    $self->catchup;

    @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);
    is_deeply(\@files1, ['foo.txt']);
    is_deeply(\@files2, ['foo.txt']);

    my $contents = read_file(File::Spec->catfile($temp2, 'foo.txt'));
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

    my $fh;

    open $fh, '>', File::Spec->catfile($temp1, 'foo.txt');
    print $fh "Hello!\n";
    close $fh;

    $self->catchup;

    @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);
    is_deeply(\@files1, ['foo.txt']);
    is_deeply(\@files2, ['foo.txt']);

    my $contents = read_file(File::Spec->catfile($temp2, 'foo.txt'));
    is $contents, "Hello!\n";

    unlink File::Spec->catfile($temp1, 'foo.txt');

    $self->catchup;

    @files1 = grep { $_ ne '.saharasync' } read_dir($temp1);
    @files2 = grep { $_ ne '.saharasync' } read_dir($temp2);

    is_deeply(\@files1, []);
    is_deeply(\@files2, []);
}

__PACKAGE__->runtests;
