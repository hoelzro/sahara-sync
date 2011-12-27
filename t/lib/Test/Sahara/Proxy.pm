package Test::Sahara::Proxy;

use strict;
use warnings;
use parent 'Class::Accessor::Fast';

use Carp ();
use IO::Socket::INET ();
use Readonly ();
use Test::TCP ();
use Time::HiRes ();

Readonly::Scalar my $WAIT_TIME_IN_USECONDS => 10_000;
Readonly::Scalar my $MAX_RETRIES           => 100;

__PACKAGE__->mk_accessors(qw/_tcp/);

sub new {
    my ( $class, %options ) = @_;

    my $tcp = Test::TCP->new(
        code => sub {
            my ( $port ) = @_;

            $ENV{'_PROXY_PORT'}        = $port;
            $ENV{'_PROXY_REMOTE_PORT'} = $options{'remote'};

            exec $^X, 't/run-proxy';
        },
    );

    return bless {
        _tcp => $tcp,
    }, $class;
}

sub port {
    my ( $self ) = @_;

    return $self->_tcp->port;
}

sub _poke_port {
    my ( $self ) = @_;

    my $port = $self->_tcp->port;
    my $sock = IO::Socket::INET->new(
        PeerHost => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'tcp',
    );

    return $sock ? 1 : 0;
}

sub _wait_for_shutdown {
    my ( $self ) = @_;

    for ( 1 .. $MAX_RETRIES ) {
        return if ! $self->_poke_port;
        Time::HiRes::usleep $WAIT_TIME_IN_USECONDS;
    }

    Carp::croak "Unable to shutdown socket operations after one second";
}

sub _wait_for_startup {
    my ( $self ) = @_;

    for ( 1 .. $MAX_RETRIES ) {
        return if $self->_poke_port;
        Time::HiRes::usleep $WAIT_TIME_IN_USECONDS;
    }

    Carp::croak "Unable to resume socket operations after one second";
}

sub kill_connections {
    my ( $self ) = @_;

    kill USR1 => $self->_tcp->pid;

    $self->_wait_for_shutdown();
}

sub resume_connections {
    my ( $self ) = @_;

    kill USR2 => $self->_tcp->pid;

    $self->_wait_for_startup();
}

1;
