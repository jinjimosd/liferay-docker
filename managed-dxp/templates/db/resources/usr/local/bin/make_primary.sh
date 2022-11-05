#!/bin/bash

local db_password="$(cat ${MARIADB_ROOT_PASSWORD_FILE})"

echo "SET GLOBAL wsrep_provider_options='pc.bootstrap=YES'" | mysql -u root -h127.0.0.1 -p"${db_password}"