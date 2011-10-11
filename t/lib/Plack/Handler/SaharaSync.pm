package Plack::Handler::SaharaSync;

use strict;
use warnings;

use AnyEvent;
use SaharaSync::Hostd::Server;

sub new {
    my ( $class, %args ) = @_;

    return bless {
        server => SaharaSync::Hostd::Server->new(%args),
    }, $class;
}

sub register_service {
    my ( $self, $app ) = @_;

    $self->{'server'}->start($app);
}

sub run {
    my ( $self, $app ) = @_;

    $self->register_service($app);
    my $cond = AnyEvent->condvar;
    $cond->recv;
}

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
