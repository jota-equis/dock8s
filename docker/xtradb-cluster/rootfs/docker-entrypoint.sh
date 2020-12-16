#!/usr/bin/env bash

. /srv/mysql/bin/docker/get-env.sh
. /srv/mysql/bin/docker/functions.sh

if [[ "$1" = "$DAEMON_NAME" ]]; then
    if ! is_daemon_running; then
        [[ ! -z $MYSQL_DATA && -d $MYSQL_DATA/lost+found ]] && rm -Rf "$MYSQL_DATA/lost+found";
        [[ ! -z $MYSQL_FILES && -d $MYSQL_FILES/lost+found ]] && rm -Rf "$MYSQL_FILES/lost+found";

        if ! is_configured || ! is_data_populated; then
            setup_node;
        fi

        [[ ! -f $DAEMON_FLAGS_FILE ]] && set_flags_file;

        fix_ownership;
        unset_vars;

        FLAGS="$DAEMON_FLAGS $DAEMON_FLAGS_EXTRA";
        
        [[ "$FLAGS" = " " ]] && FLAGS=$(cat $DAEMON_FLAGS_FILE)
        
        exec gosu $MYSQL_USER:$MYSQL_GROUP $DAEMON_BIN $FLAGS;
    fi
fi

unset_vars:

exec gosu $MYSQL_USER:$MYSQL_GROUP bash;
