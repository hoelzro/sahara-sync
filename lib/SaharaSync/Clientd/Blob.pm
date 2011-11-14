package SaharaSync::Clientd::Blob;

use Moose;

has name => (
    is       => 'ro',
    required => 1,
);

has _root => (
    is       => 'ro',
    required => 1,
    init_arg => 'root',
);

sub path {
    my ( $self ) = @_;

    return File::Spec->catfile($self->_root, $self->name);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

# ABSTRACT: Representation of sync directory files

=head1 SYNOPSIS

=head1 DESCRIPTION

Blob objects represent files in a clientd's sync directory.  They
are called blobs because Sahara Sync doesn't really care about their
contents.

=head1 ATTRIBUTES

=head2 name

The name of the blob.  With respect to the server, a blob's URI
is found at http://server.tld/blobs/$blob->name.  With respect to
the client, a blob's location on disk is $blob->name, relative to
the client's sync dir root.

=head1 METHODS

=head2 path

Returns the absolute path to this blob.

=cut
