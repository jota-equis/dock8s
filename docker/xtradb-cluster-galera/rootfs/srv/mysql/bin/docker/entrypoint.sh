#!/usr/bin/env bash

. /srv/mysql/bin/docker/get-env.sh
. /srv/mysql/bin/docker/functions.sh

init_config;

case $CUR_STATUS in
0)
logmsg "This is the first node in a stateful set and it has no grant tables and no other nodes are up - initialize"
mv $MARIADB_CONFIG_EXTRA/wsrep.cnf $MARIADB_CONFIG_EXTRA/wsrep.cnf.bak
rm -Rf $MARIADB_DATA/*
mysqld --initialize-insecure --datadir=$MARIADB_DATA/ --user=$MARIADB_USER
mysqld --defaults-file=$MARIADB_CNF --user=$MARIADB_USER --datadir=$MARIADB_DATA/ --skip-networking --log-error=$MARIADB_LOG/mysqld.log &

for i in {1..30}; do
  if $(mysql -u root -S $MARIADB_SOCK -Nse "SELECT 1;" > /dev/null 2>&1) ; then
    break
  fi
  sleep 2
done

[[ $i -eq 30 ]] && logerror "Failed to initialize";

if $(/usr/bin/mysqladmin -S $MARIADB_SOCK -u root password "${MYSQL_ROOT_PASSWORD}" 2>/dev/null) ; then
    write_user_conf
else
    logerror "Failed to set root password";
fi

setup_users;

killall mysqld

until [ $(pgrep -c mysqld) -eq 0 ]; do sleep 1; done
    logmsg "MySQL shutdown"
    mv $MARIADB_CONFIG_EXTRA/wsrep.cnf.bak $MARIADB_CONFIG_EXTRA/wsrep.cnf
;;

1)
    logmsg "This is the first node in a stateful set, it has no grant tables, no other cluster nodes are up and is set to start from backup";
    logerror "Failed :: Restore from backup not yet supported!";
;;

2)
    logmsg "This is not the first node in a stateful set and has no grant tables and at least one node is up - SST"
    rm -rf $MARIADB_DATA/*
    write_user_conf
;;

3)
    logmsg "Grant tables are present just attempt a start"
    write_user_conf
;;
esac;

if [ ! is_cluster_up ] && [ is_master_node ]; then
    [[ -f ${GALERA_GRASTATE} ]] && sed -i "s/^safe_to_bootstrap.*$/safe_to_bootstrap: 1/g" ${GALERA_GRASTATE}
    BOOTARGS="--wsrep-new-cluster"
fi

trap 'kill ${!}; term_handler' SIGKILL SIGTERM SIGHUP SIGINT EXIT

logmsg "Starting MySQL"
eval "mysqld --defaults-file=$MARIADB_CNF --datadir=$MARIADB_DATA --user=$MARIADB_USER $BOOTARGS 2>&1 &"

CUR_PID="$!"

while true
do 
    tail -f /dev/null & wait ${!}
done
