use strict;
use warnings;
use parent 'Test::Sahara::Stream::Writer';

use JSON ();

sub deserialize {
    my ( $self, $json ) = @_;

    return JSON->new->utf8->allow_nonref->decode($json);
}

sub mime_type {
    return 'application/json';
}

__PACKAGE__->new->runtests;
