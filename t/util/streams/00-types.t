use strict;
use warnings;

use Test::More;

use IO::String;
use SaharaSync::Stream::Reader;
use SaharaSync::Stream::Writer;

my @types = (
    'application/json',
    'application/json; charset=utf-8',
);
## text/json?
## application/json; charset=utf-16be?

plan tests => @types * 2;

foreach my $type (@types) {
    my $fake_stream = IO::String->new;
    my $reader      = SaharaSync::Stream::Reader->for_mimetype($type);
    my $writer      = SaharaSync::Stream::Writer->for_mimetype($type, writer => $fake_stream);

    ok $reader, "reader should be present for $type";
    ok $writer, "writer should be present for $type";
}
