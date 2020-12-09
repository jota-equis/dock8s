#!/usr/bin/env bash

. /srv/mysql/bin/docker/get-env.sh
. /srv/mysql/bin/docker/functions.sh

[[ ! -z $MYSQL_DATA && -d $MYSQL_DATA/lost+found ]] && rm -Rf "$MYSQL_DATA/lost+found";

# .dock8s_has_bootstrap
if [[ ! -f "${MYSQL_HOME}/.run_flags" ]]; then
    setup_node;
fi
