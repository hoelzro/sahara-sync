package SaharaSync::Stream::Writer::JSON;

use Moose;
use JSON qw(encode_json);

use namespace::clean -except => 'meta';

with 'SaharaSync::Stream::Writer';

has first_write => (
    is       => 'rw',
    isa      => 'Bool',
    default  => 1,
    init_arg => undef,
);

sub begin_stream {
    return '[';
}

sub end_stream {
    return ']';
}

sub serialize {
    my ( $self, $object ) = @_;

    my $json = JSON->new->utf8->allow_nonref;

    if($self->first_write) {
        $self->first_write(0);
        return $json->encode($object);
    } else {
        return ',' . $json->encode($object);
    }
}

__PACKAGE__->meta->make_immutable;
1;
