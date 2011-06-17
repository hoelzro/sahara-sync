use strict;
use warnings;
use parent 'Test::Sahara::Stream::Reader';

use JSON ();

sub begin_stream {
    my ( $self, $writer ) = @_;

    $self->{'first'} = 1;
    $writer->write('[');
}

sub end_stream {
    my ( $self, $writer ) = @_;

    $writer->write(']');
}

sub serialize {
    my ( $self, $writer, $data ) = @_;

    if($self->{'first'}) {
        $self->{'first'} = 0;
    } else {
        $writer->write(',');
    }

    $writer->write(JSON->new->utf8->allow_nonref->encode($data));
}

sub mime_type {
    return 'application/json';
}

__PACKAGE__->new->runtests;
