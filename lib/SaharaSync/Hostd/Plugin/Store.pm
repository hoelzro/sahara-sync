## no critic (RequireUseStrict)
package SaharaSync::Hostd::Plugin::Store;

## use critic (RequireUseStrict)
use Moose::Role;

use Carp qw(croak);;
use Encode qw(encode_utf8 decode_utf8);
use Readonly;
use SaharaSync::X::BadContext;
use SaharaSync::X::InvalidArgs;
use namespace::clean;

Readonly my $MAX_METADATA_KEY_LEN   => 255;
Readonly my $MAX_METADATA_VALUE_LEN => 255;

requires 'create_user';
requires 'remove_user';
requires 'load_user_info';
requires 'fetch_blob';
requires 'store_blob';
requires 'delete_blob';
requires 'fetch_changed_blobs';

around fetch_blob => sub {
    my $orig = shift;
    my $self = shift;

    unless(wantarray) {
        SaharaSync::X::BadContext->throw({
            context => (defined(wantarray) ? 'scalar' : 'void'),
        });
    }

    if(my ( $blob, $metadata ) = $self->$orig(@_)) {
        foreach my $k (keys %$metadata) {
            my $v = delete $metadata->{$k};
            $k = decode_utf8($k);
            $v = decode_utf8($v);
            $metadata->{$k} = $v;
        }
        return ( $blob, $metadata );
    } else {
        return;
    }
};

before store_blob => sub {
    my ( $self, $user, $name, $contents, $metadata ) = @_;

    if(defined($metadata) && ref($metadata) ne 'HASH') {
        SaharaSync::X::InvalidArgs->throw({
            message => 'store_blob metadata must be a hash reference',
        });
    }

    if(defined $metadata) {
        foreach my $k (keys %$metadata) {
            my $v = delete $metadata->{$k};
            if(length $k > $MAX_METADATA_KEY_LEN) {
                SaharaSync::X::InvalidArgs->throw({
                    message => 'Metadata key is too long',
                });
            }
            if(defined $v && length $v > $MAX_METADATA_VALUE_LEN) {
                SaharaSync::X::InvalidArgs->throw({
                    message => 'Metadata value is too long',
                });
            }
            $k = encode_utf8($k);
            $v = encode_utf8($v) if defined $v;
            $metadata->{lc $k} = $v;
        }
    }


    unless(eval { $contents->can('read') } || ref($contents) eq 'GLOB') {
        SaharaSync::X::InvalidArgs->throw({
            message => 'store_blob contents must support the read operation',
        });
    }
};

before delete_blob => sub {
    my ( $self, $user, $name, $revision ) = @_;

    unless(defined $revision) {
        SaharaSync::X::InvalidArgs->throw({
            message => 'Revision must be defined',
        });
    }
};

1;

__END__

# ABSTRACT: Base role for storage plugins

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 REQUIRED METHODS

=head2 $store->create_user($username, $password)

Creates a new user with username C<$username> and
password C<$password>.  Returns 1 if the user was
successfully created, or 0 otherwise.

=head2 $store->remove_user($username)

Deletes a user and all of his/her files.

=head2 $store->load_user_info($username)

Returns a hash reference containing the password
hash for C<$username> under the key 'password_hash'.

=head2 $store->fetch_blob($user, $blob)

Returns a list of two elements; the first is an L<IO::Handle>-like
object that is tied to the contents of the blob, and the second is
an opaque identifier that specifies the current revision of the blob.
If the blob does not exist for the given user, an empty list is returned.
If this method is called in anything other than list context, a
L<SaharaSync::X::BadContext> exception is thrown. (This is mainly to prevent
calls to this method that leak information; this may be changed in the future)
If C<$user> does not exist, a L<SaharaSync::X::BadUser> exception is thrown.

=head2 $store->store_blob($user, $blob, $handle, $revision)

Stores the contents of C<$handle> in a blob called C<$blob>
for user C<$user>.  C<$handle> is NOT necessarily an L<IO::Handle>;
the only interface it must implement is the read method
(see L<PSGI/"The Input Stream"> for details).  If creating a new blob,
C<$revision> must not be specified (or specified as undef); otherwise,
the current revision of the blob should be provided.  If the storage operation
is successful (the blob is new, or the provided revision matches the current),
a new opaque revision identifer is returned; otherwise, undef is returned.

=head2 $store->delete_blob($user, $blob, $revision)

Deletes the blob C<$blob> for user C<$user>.  If the blob does not exist, a
L<SaharaSync::X::NoSuchBlob> exception is thrown.  C<$revision> should be the
current revision of the blob.  If the delete operation is successful (the
revisions match), a new opaque revision identifer is returned; otherwise,
undef is returned.

=head2 $store->fetch_changed_blobs($user, $since_revision)

Returns an array of unique blob names that have changed since
C<$since_revision>.  C<$since_revision> may be omitted; in that case, all
blobs for the given user are returned.  If C<$since_revision> is not a known
revision, a L<SaharaSync::X::BadRevision> exception is thrown.

=head1 SEE ALSO

SaharaSync::Hostd

=cut
