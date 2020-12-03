#!/usr/bin/env bash

. /srv/mysql/bin/docker/get-env.sh
. /srv/mysql/bin/docker/functions.sh

logmsg "Starting XtraDB MariaDB server"

get_boot_envs;
# trap 'kill ${!}; term_handler' SIGKILL SIGTERM SIGHUP SIGINT EXIT
exec mysqld --defaults-file=${MARIADB_CNF} --datadir=${MARIADB_DATA} --user=${MARIADB_USER} ${BOOTARGS};

#wait ${!}
