package SaharaSync::Hostd::Server;

use Moose;
use Twiggy::Server;

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
}

sub stop {
    my ( $self ) = @_;

    $self->twiggy(undef);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut
