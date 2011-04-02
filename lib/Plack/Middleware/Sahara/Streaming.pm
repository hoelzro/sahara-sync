package Plack::Middleware::Sahara::Streaming;

use strict;
use warnings;

use parent 'Plack::Middleware';

sub call {
    my ( $self, $env ) = @_;

    my $streaming = $env->{'psgi.nonblocking'} &&
		    $env->{'psgi.streaming'}   &&
		    ($env->{'HTTP_CONNECTION'} || '') ne 'close';

    $env->{'sahara.streaming'} = $streaming;

    return $self->app->($env);
}

1;

__END__

=head1 NAME

Plack::Middleware::Sahara::Streaming - Populates PSGI env with sahara.streaming

=head1 VERSION

0.01

=head1 SYNOPSIS

  use Plack::Builder;

  builder {
    enable 'Sahara::Streaming';
    $app;
  };

=head1 DESCRIPTION

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
