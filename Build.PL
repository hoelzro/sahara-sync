#!/usr/bin/env perl

use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
    build_requires    => {
        'Pod::Readme'     => 0,
        'TAP::Harness'    => 0,
        'Test::Deep'      => 0,
        'Test::More'      => 0,
        'Test::Exception' => 0,
    },
    create_readme     => 1,
    dist_abstract     => 'Sync freely.',
    dist_author       => 'Rob Hoelz <rob@hoelz.ro>',
    dist_name         => 'SaharaSync',
    dist_version      => '0.01',
    license           => 'unknown', # AGPL 3
    module_name       => 'SaharaSync',
    recursive_test_files => 1,
    requires          => {
        'AnyEvent::Filesys::Notify'       => 0,
        'AnyEvent::HTTP'                  => 0,
        'DBD::Pg'                         => 0,
        'DBI'                             => 0,
        'File::Path'                      => 0,
        'File::Slurp'                     => 0,
        'File::Spec'                      => 0,
        'MIME::Base64'                    => 0,
        'Moose'                           => 0,
        'Plack'                           => 0,
        'Plack::Middleware::Auth::Digest' => 0,
        'Plack::Middleware::Options'      => 0,
        'perl'                            => '5.10.0',
        'Twiggy'                           => 0,
    },
    script_files      => [
    ],
    use_tap_harness   => 1,
);
$build->create_build_script;
