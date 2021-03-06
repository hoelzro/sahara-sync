package Test::Sahara::Proxy;

use strict;
use warnings;
use parent 'Class::Accessor::Fast';

use Carp ();
use LWP::UserAgent ();
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
    my $req  = HTTP::Request->new(GET => "http://localhost:$port/");
    my $ua   = LWP::UserAgent->new;
    $ua->timeout($WAIT_TIME_IN_USECONDS / 1_000_000);

    my $res = $ua->request($req);
    return $res->code < 500; # client errors (like 404) are still valid
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
    my ( $self, %opts ) = @_;

    my $preserve_existing = $opts{'preserve_existing'};

    if($preserve_existing) {
        kill USR2 => $self->_tcp->pid;
    } else {
        kill USR1 => $self->_tcp->pid;
    }

    Time::HiRes::usleep(250_000);

    $self->_wait_for_shutdown();
}

sub resume_connections {
    my ( $self ) = @_;

    kill USR1 => $self->_tcp->pid;

    Time::HiRes::usleep(250_000);

    $self->_wait_for_startup();
}

1;
