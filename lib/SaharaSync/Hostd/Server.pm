package SaharaSync::Hostd::Server;

use Moose;
use Twiggy::Server 0.1025;

use namespace::clean -except => 'meta';

has twiggy => (
    is => 'rw'
);

sub BUILDARGS {
    my ( $self, %args ) = @_;

    return {
        twiggy => Twiggy::Server->new(%args),
    };
}

sub start {
    my ( $self, $app ) = @_;

    $self->twiggy->register_service($app);
    return;
}

sub stop {
    my ( $self ) = @_;

    delete $self->twiggy->{'listen_guards'}; # naughty, touching internals
    $self->twiggy(undef);
    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
