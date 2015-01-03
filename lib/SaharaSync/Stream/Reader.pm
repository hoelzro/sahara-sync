package SaharaSync::Stream::Reader;

use Moose::Role;
use feature 'switch';
no warnings 'experimental::smartmatch';

use namespace::clean -except => 'meta';

has [qw/on_read_object on_end/] => (
    is      => 'rw',
    isa     => 'CodeRef',
    default => sub { sub {} },
);

has on_parse_error => (
    is      => 'rw',
    isa     => 'CodeRef',
    default => sub { sub {
        my ( undef, $ex ) = @_;

        $ex->throw;
    } },
);

requires 'feed';

sub for_mimetype {
    my ( $class, $mime_type ) = @_;

    $mime_type =~ s/;.*$//;

    given($mime_type) {
        when('application/json') {
            require SaharaSync::Stream::Reader::JSON;
            return SaharaSync::Stream::Reader::JSON->new;
        }
    }
}

1;

__END__

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=cut
