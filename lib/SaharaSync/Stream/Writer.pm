package SaharaSync::Stream::Writer;

use Moose::Role;

use feature 'switch';
no warnings 'experimental::smartmatch';

use Carp qw(croak);

use namespace::clean -except => 'meta';

has writer => (
    is       => 'ro',
    required => 1,
);

has closed => (
    is       => 'rw',
    isa      => 'Bool',
    init_arg => undef,
    default  => 0,
);

requires 'begin_stream';
requires 'serialize';
requires 'end_stream';

sub BUILD {}
sub DEMOLISH {}

after BUILD => sub {
    my ( $self ) = @_;

    $self->writer->write($self->begin_stream);
};

before DEMOLISH => sub {
    my ( $self ) = @_;

    $self->close unless $self->closed;
};

sub write_object {
    my ( $self, $object ) = @_;

    if($self->closed) {
        croak "Writer is closed";
    }

    $self->writer->write($self->serialize($object));
}

sub write_objects {
    my $self = shift;

    if($self->closed) {
        croak "Writer is closed";
    }

    foreach (@_) {
        $self->write_object($_);
    }
}

sub close {
    my ( $self ) = @_;

    if($self->closed) {
        croak "Writer is closed";
    }

    $self->writer->write($self->end_stream);
    $self->writer->close;
    $self->closed(1);
}

sub for_mimetype {
    my ( $class, $mime_type, %opts ) = @_;

    $mime_type =~ s/;.*$//;

    given($mime_type) {
        when('application/json') {
            require SaharaSync::Stream::Writer::JSON;
            return SaharaSync::Stream::Writer::JSON->new(%opts);
        }
    }
}

1;

__END__

=head1 SYNOPSIS

  use Moose;
  with 'SaharaSync::Stream::Writer';

  sub serialize {
    my ( $self, $object ) = @_;
  }

=head1 DESCRIPTION

=head1 REQUIRED METHODS

=head2 $writer->serialize($object)

=head1 METHODS

=cut
