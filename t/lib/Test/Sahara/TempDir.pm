package Test::Sahara::TempDir;

use strict;
use warnings;
use parent 'Path::Class::Dir';

use File::Temp ();

sub new {
    my ( $class ) = @_;

    my $temp_dir = File::Temp->newdir;
    my $self     = Path::Class::Dir::new($class, $temp_dir->dirname);
    $self->{'temp_dir'} = $temp_dir;
    return $self;
}

sub dirname {
    my ( $self ) = @_;

    return $self->stringify;
}

1;
