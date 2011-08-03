#!/bin/bash

# This script assumes you have a MySQL instance and PostgreSQL instance
# running on the default ports and sockets on localhost.  It also assumes
# your MySQL instance has a root user with no password, and your default
# PostgreSQL user has no password as well.

info=$(caller)
info=${info% *}

if [[ "$info" -eq 0 ]]; then
    echo -e "\033[31mUsage: . $0\033[0m"
fi

export TEST_PGDATABASE=sahara-test
export TEST_MYHOST=127.0.0.1
export TEST_MYUSER=root
export TEST_MYDATABASE=sahara

dropdb $TEST_PGDATABASE 2>/dev/null
createdb $TEST_PGDATABASE

psql -X -f schema.psql $TEST_PGDATABASE

mysql -h $TEST_MYHOST -u $TEST_MYUSER <<SQL
drop database if exists $TEST_MYDATABASE;
create database $TEST_MYDATABASE;
SQL
mysql -h $TEST_MYHOST -u $TEST_MYUSER $TEST_MYDATABASE < schema.mysql
