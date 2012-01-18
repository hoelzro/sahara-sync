package Test::Sahara::Client;

use strict;
use warnings;
use parent 'Test::Sahara::ChildProcess';

use Carp qw(confess);
use File::Slurp qw(read_file);
use File::Temp;
use Test::More;

__PACKAGE__->mk_accessors(qw/sync_dir log_file/);

sub new {
    my ( $class, %opts ) = @_;

    my $client_num    = $opts{'num'};
    my $upstream_port = $opts{'port'};
    my $poll_interval = $opts{'poll_interval'};
    my $sync_dir      = $opts{'sync_dir'};
    my $log_file      = File::Temp->new;

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
        $ENV{'_CLIENTD_LOG_FILE'}      = $log_file;

        exec $^X, 't/run-test-client';
    });

    $self->sync_dir($sync_dir);
    $self->log_file($log_file);

    return $self;
}

sub check {
    my ( $self ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $log_contents = read_file($self->log_file);

    is $log_contents, '', 'error log for clients should be empty';

    return Test::Sahara::ChildProcess::check($self);
}

1;
