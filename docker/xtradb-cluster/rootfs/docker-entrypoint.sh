#!/usr/bin/env bash

if [[ "$1" = 'mysqld' ]]; then
    [[ $(pgrep -c "$1") = 0 ]] || { echo "There is a running instance ..."; return 0; }

    FLAGS_FILE="${MYSQL_HOME:-/srv/mysql}/.run_flags";

    [[ ! -f $FLAGS_FILE || ! -d ${MYSQL_HOME}/data || -z "$(ls -A "${MYSQL_HOME}/data/")" ]] && /srv/mysql/bin/docker/bootstrap.sh;

    if [[ -f $FLAGS_FILE ]]; then
        exec gosu "${MYSQL_USER:-mysql}" "${@}" $(cat $FLAGS_FILE) &

        #wait ${!}
    fi
    
    tail -f /dev/null;
fi
