#!/usr/bin/env perl

# Copyright 2011 Rob Hoelz.
#
# This file is part of Sahara Sync.
#
# Sahara Sync is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Sahara Sync is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Sahara Sync.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use lib 'lib';

use Plack::Runner;
use Twiggy;
use SaharaSync::Hostd;

my $app = SaharaSync::Hostd->new(
    storage => {
        type => 'DBIWithFS',
        dsn  => 'dbi:Pg:database=sahara',
        fs_storage_path => '/tmp/sahara',
    },
)->to_app;

my $runner = Plack::Runner->new(
    server => 'Twiggy',
);
$runner->parse_options(qw/--port 5982/);
$runner->run($app);
