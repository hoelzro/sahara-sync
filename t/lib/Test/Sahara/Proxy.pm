package Test::Sahara::Proxy;

use strict;
use warnings;
use parent 'Class::Accessor::Fast';

use Test::TCP ();

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

sub kill_connections {
    my ( $self ) = @_;

    kill USR1 => $self->_tcp->pid;
}

sub resume_connections {
    my ( $self ) = @_;

    kill USR2 => $self->_tcp->pid;
}

1;
