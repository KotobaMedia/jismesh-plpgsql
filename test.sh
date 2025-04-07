#!/bin/bash -e

# A script to run tests locally.

psql -c "DROP DATABASE IF EXISTS jismesh_plpgsql_test;"
psql -c "CREATE DATABASE jismesh_plpgsql_test;"

psql -d jismesh_plpgsql_test -f tests/setup.sql
psql -d jismesh_plpgsql_test -f jismesh.sql

pg_prove -d jismesh_plpgsql_test -f tests/*_test.sql
# -S client_min_messages=DEBUG
