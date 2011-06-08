use strict;
use warnings;

use Cwd qw(realpath);
use FindBin;
use File::Spec;
use File::Temp;
use SaharaSync::Hostd::Plugin::Store::DBIWithFS;
use Test::Sahara::Storage;

eval {
    require DBD::SQLite;
};
if($@) {
    plan skip_all => 'You must install DBD::SQLite to run this test';
    exit;
}

my $tempfile = File::Temp->new;
my $schema   = realpath(File::Spec->catfile($FindBin::Bin,
    (File::Spec->updir) x 4, 'schema.sqlite'));

my $fh;
open $fh, '<', $schema or die $!;
$schema = do {
    local $/;
    <$fh>;
};
close $fh;

my $dsn = "dbi:SQLite:dbname=$tempfile";

sub reset_db {
    unlink $tempfile;
    my $dbh = DBI->connect($dsn, '', '', {
        RaiseError                       => 1,
        PrintError                       => 0,
        sqlite_allow_multiple_statements => 1,
    });

    $dbh->do($schema);

    $dbh->do(<<SQL);
INSERT INTO users (username, password) VALUES ('test', 'abc123')
SQL

    $dbh->do(<<SQL);
INSERT INTO users (username, password) VALUES ('test2', 'abc123')
SQL

    $dbh->disconnect;
}

plan tests => 2;
my $tempdir = File::Temp->newdir;
reset_db;

## we need to enable the foreign pragma somehow...
my $store = SaharaSync::Hostd::Plugin::Store::DBIWithFS->new(
    dsn             => $dsn,
    username        => '',
    password        => '',
    fs_storage_path => $tempdir->dirname,
);

run_store_tests $store, "DBIWithFS: SQLite - new dbh";

reset_db;
$tempdir = File::Temp->newdir;

$store = SaharaSync::Hostd::Plugin::Store::DBIWithFS->new(
    dbh             => DBI->connect($dsn, '', ''),
    fs_storage_path => $tempdir->dirname,
);

run_store_tests $store, "DBIWithFS: SQLite - existing dbh";
