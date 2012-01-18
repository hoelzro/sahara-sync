package Test::Sahara::ChildProcess;

use strict;
use warnings;
use autodie qw(pipe);
use parent qw/Test::TCP Class::Accessor::Fast/;

use IO::Handle;
use POSIX qw(dup2);
use Test::More;

use namespace::clean;

__PACKAGE__->mk_accessors(qw/pipe has_been_checked/);

sub new {
    my ( $class, $code ) = @_;

    my ( $read, $write );

    pipe $read, $write;

    my $self = Test::TCP::new($class, code => sub {
        my ( $port ) = @_;

        close $read;

        dup2 fileno($write), 3 or die $!;
        close $write;

        return $code->($port);
    });

    close $write;
    my $pipe = IO::Handle->new;
    $pipe->fdopen(fileno($read), 'r');
    close $read;

    $pipe->blocking(0);

    $self->pipe($pipe);
    $self->has_been_checked(0);

    return $self;
}

sub check {
    my ( $self ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    $self->has_been_checked(1);

    $self->stop;

    my $pipe   = $self->pipe;
    my $buffer = '';
    my $bytes  = $pipe->sysread($buffer, 1);
    $pipe->close;

    my $ok = 1;
    $ok = is($bytes, 1, 'The client should write a status byte upon safe exit') && $ok;
    $ok = is($buffer, 0, 'No errors should occur in the client')                && $ok;

    return $ok;
}

sub DESTROY {
    my ( $self ) = @_;

    unless($self->has_been_checked) {
        fail "client was never checked";
    }
}

sub pause {
    my ( $self ) = @_;

    kill SIGSTOP => $self->pid;
}

sub resume {
    my ( $self ) = @_;

    kill SIGCONT => $self->pid;
}

1;
