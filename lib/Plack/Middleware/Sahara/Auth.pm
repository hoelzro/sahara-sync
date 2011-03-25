package Plack::Middleware::Sahara::Auth;

use strict;
use warnings;
use parent 'Plack::Middleware::Auth::Digest';

our $VERSION = '0.01';

sub new {
    my $class = shift;

    my %options;

    if(@_ == 1) {
        %options = %{ $_[0] };
    } else {
        %options = @_;
    }

    my $store = delete $options{'store'};

    my %params = (
        realm           => 'Sahara',
        secret          => 'my$3kr3t',
        password_hashed => 1,
        authenticator   => sub {
            my ( $username, $env ) = @_;

            my $info = $store->load_user_info($username);
            return unless $info;
            return unpack('H*', $info->{'password_hash'});
        },
        %options,
    );

    return bless Plack::Middleware::Auth::Digest->new(%params), $class;
}

1;

__END__

=head1 NAME

Plack::Middleware::Sahara::Auth - Simple middleware wrapping Auth::Digest

=head1 VERSION

0.01

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=head1 AUTHOR

Rob Hoelz, C<< rob at hoelz.ro >>

=head1 BUGS

=head1 COPYRIGHT & LICENSE

Copyright 2011 Rob Hoelz.

This file is part of Sahara Sync.

Sahara Sync is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Sahara Sync is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with Sahara Sync.  If not, see <http://www.gnu.org/licenses/>.

=head1 SEE ALSO

L<SaharaSync>

=cut
