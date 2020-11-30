#!/usr/bin/env bash

. /srv/mysql/bin/docker/get-env.sh
. /srv/mysql/bin/docker/functions.sh

[[ -f ${MARIADB_TMP}/bootargs ]] && { . ${MARIADB_TMP}/bootargs; rm -f ${MARIADB_TMP}/bootargs; };

logmsg "Starting MySQL"
mysqld --defaults-file=${MARIADB_CNF} --datadir=${MARIADB_DATA} --user=${MARIADB_USER} ${BOOTARGS} 2>&1 &

wait ${!}
