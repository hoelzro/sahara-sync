package SaharaSync::Clientd;

use strict;
use warnings;

use AnyEvent::Filesys::Notify;
use AnyEvent::WebService::Sahara;
use File::Path qw(make_path);
use File::Slurp qw(read_file);
use File::Spec;

our $VERSION = '0.01';

my $UPSTREAM = 'http://localhost:5000';
my $USER     = 'test';
my $PASSWORD = 'abc123';
my $SYNC_DIR = '~/Sandbox';

my $client;
my $fs_notify;

sub to_app {
    my ( $self ) = @_;

    # find out our last sync timestamp (0 if none)
    # get the list of changes from the server for that timestamp
    # for each change:
    #   stat the file the blob points at
    #   if the file's mtime or ctime is newer than the last sync timestamp, then mark it as conflicted (unless contents match?)
    #   pull the file from the server

    # crawl over the sync directory, and for each file whose timestamp is newer than the last sync
    #   if not conflicted, push to server

    # how does last sync get updated when we're streaming changes in?

    # if capabilities contains 'streaming'
    #   set up persistent HTTP connection to /changes, make sure to handle errors!
    # else
    #   set up polling timer to check /changes
    # don't accept changes that came from us!
    
    # if changes come in, but we can't push to server, do something about that!

    # what if someone changes their sync dir?
    # what if someone adds/changes/deletes files when the client isn't running?
    $SYNC_DIR =~ s/^~/(getpwuid($<))[7]/e;
    make_path($SYNC_DIR);

    $client = AnyEvent::WebService::Sahara->new(
        url      => $UPSTREAM,
        user     => $USER,
        password => $PASSWORD,
    );

    $fs_notify = AnyEvent::Filesys::Notify->new(
        dirs => [ $SYNC_DIR ],
        cb   => sub {
            my ( @events ) = @_;

            foreach my $event (@events) {
                my $blob = $event->path;
                $blob    = File::Spec->abs2rel($blob, $SYNC_DIR); 

                next if $event->is_dir; # we ignore directories for now

                my $contents;
                unless($event->is_deleted) {
                    ## what if we don't have read permissions?
                    $contents = read_file($event->path, err_mode => 'quiet');
                    next unless defined $contents;
                }

                ## attach metadata: MIME Type File Size Hash of File Contents
                ## is encryption/filtration/etc handled by us, or AE::WS::Sahara?
                $client->put_blob($blob, $contents, sub {
                    my ( $ok ) = @_;

                    if($ok) {
                        print STDERR "Successfully wrote $blob\n";
                    } else {
                        print STDERR "Failed to  write $blob\n";
                    }
                });
            }
        },
    );


    return sub {
        return [
            200,
            [
                'Content-Type' => 'text/plain',
            ],
            [
                'Nothing...yet =)'
            ],
        ];
    };
}


1;

__END__

=head1 NAME

SaharaSync::Clientd

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
