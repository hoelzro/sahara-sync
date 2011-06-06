## no critic (RequireUseStrict)
package Plack::Middleware::Sahara::Streaming;

## use critic (RequireUseStrict)
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

# ABSTRACT: Populates PSGI env with sahara.streaming

=head1 SYNOPSIS

  use Plack::Builder;

  builder {
    enable 'Sahara::Streaming';
    $app;
  };

=head1 DESCRIPTION

=cut
