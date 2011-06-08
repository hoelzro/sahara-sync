use strict;
use warnings;

use SaharaSync::Hostd::Plugin::Store::DBIWithFS;
use Test::Sahara::Storage;

use File::Temp;

eval {
    require DBD::Pg;
};
if($@) {
    plan skip_all => 'You must install DBD::Pg to run this test';
    exit;
}

my $catalog  = $ENV{'TEST_PGDATABASE'};
my $schema   = 'public';
my $username = $ENV{'TEST_PGUSER'} || '';
my $password = $ENV{'TEST_PGPASS'} || '';

unless(defined $catalog) {
    plan skip_all => 'You must define TEST_PGDATABASE to run this test';
    exit;
}

my $dsn = "dbi:Pg:dbname=$catalog";
if(my $host = $ENV{'TEST_PGHOST'}) {
    $dsn .= ":host=$host";
}
if(my $port = $ENV{'TEST_PGPORT'}) {
    $dsn .= ":port=$port";
}

sub reset_db {
    my $dbh = DBI->connect($dsn, $username, $password, {
        RaiseError => 1,
        PrintError => 0,
    });
    my @tables = $dbh->tables($catalog, $schema, '%', 'TABLE'); 

    foreach my $table (@tables) {
        $dbh->do("DELETE FROM $table");
    }

    $dbh->do(<<SQL);
INSERT INTO users (username, password)
VALUES
    ('test', 'abc123'),
    ('test2', 'abc123')
SQL

    $dbh->disconnect;
}

plan tests => 2;
my $tempdir = File::Temp->newdir;
reset_db;

my $store = SaharaSync::Hostd::Plugin::Store::DBIWithFS->new(
    dsn             => $dsn,
    username        => $username,
    password        => $password,
    fs_storage_path => $tempdir->dirname,
);

run_store_tests $store, "DBIWithFS: PostgreSQL - new dbh";

reset_db;
$tempdir = File::Temp->newdir;

$store = SaharaSync::Hostd::Plugin::Store::DBIWithFS->new(
    dbh             => DBI->connect($dsn, $username, $password),
    fs_storage_path => $tempdir->dirname,
);

run_store_tests $store, "DBIWithFS: PostgreSQL - existing dbh";
