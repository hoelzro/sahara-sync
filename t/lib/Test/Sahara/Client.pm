package Test::Sahara::Client;

use strict;
use warnings;
use parent 'Test::Sahara::ChildProcess';

use Carp qw(confess);
use File::Temp;

__PACKAGE__->mk_accessors(qw/sync_dir/);

sub new {
    my ( $class, %opts ) = @_;

    my $client_num    = $opts{'num'};
    my $upstream_port = $opts{'port'};
    my $poll_interval = $opts{'poll_interval'};
    my $sync_dir      = $opts{'sync_dir'};

    $sync_dir ||= File::Temp->newdir;

    confess "client num required"    unless $client_num;
    confess "upstream port required" unless $upstream_port;
    confess "poll interval required" unless $poll_interval;

    my $self = Test::Sahara::ChildProcess::new($class, sub {
        my ( $port ) = @_;

        $ENV{'_CLIENTD_PORT'}          = $port;
        $ENV{'_CLIENTD_UPSTREAM'}      = 'http://localhost:' . $upstream_port;
        $ENV{'_CLIENTD_ROOT'}          = $sync_dir->dirname;
        $ENV{'_CLIENTD_POLL_INTERVAL'} = $poll_interval;
        $ENV{'_CLIENTD_NUM'}           = $client_num;

        exec $^X, 't/run-test-client';
    });

    $self->sync_dir($sync_dir);

    return $self;
}

1;
