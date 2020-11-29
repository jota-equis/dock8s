#!/usr/bin/env bash

. /srv/scripts/get-env.sh
. /srv/scripts/functions.sh

mk_appdir;
add_peers;
sleep 1;

logmsg "Setting default config";
set_file_conf "${MARIADB_CONFIG}/my.cnf";
set_file_conf "${MARIADB_CONFIG_EXTRA}/binlog.cnf";
set_file_conf "${MARIADB_CONFIG_EXTRA}/wsrep.cnf";
set_file_conf "${MARIADB_CONFIG_EXTRA}/sst.cnf";
set_file_conf "${MARIADB_CONFIG_EXTRA}/xtrabackup.cnf";
[[ -d "${GALERA_BACKUP}" ]] && set_file_conf "${MARIADB_CONFIG_EXTRA}/file.cnf";


if [ $GALERA_NODEID -eq 0 ] && [ ! -d "$MARIADB_DATA/mysql" ] && [ $GALERA_CLUSTER_UP -eq 0 ]; then
    INIT=0

    [[ "${STARTFROMBACKUP}" = "true" && -d "${GALERA_BACKUP}" ]] && INIT=1
elif [ $GALERA_CLUSTER_UP -eq 1 ] && [ ! -d "$MARIADB_DATA/mysql" ]; then
    INIT=2
elif [ -d "$MARIADB_DATA/mysql" ]; then
    INIT=3
fi

if [ $INIT -eq -1 ]; then
  echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] ENV variables not set correctly or cluster down and this is not node-0"
  echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] need at least:"
  echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] MYSQL_ROOT_PASSWORD=<password of all root users>"
  echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] SSTUSER_PASSWORD=<password for SST user>"
  echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] CLUSTER_NAME=<name of cluster>"
  exit 1
fi

case $INIT in
0)
echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] This is the first node in a stateful set and it has no grant tables and no other nodes are up - initialize"
mv $MARIADB_CONFIG_EXTRA/wsrep.cnf $MARIADB_CONFIG_EXTRA/wsrep.cnf.bak
rm -rf $MARIADB_DATA/*
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

mysql -Nse "SET @@SESSION.SQL_LOG_BIN=0;CREATE USER IF NOT EXISTS 'root'@'%';"
mysql -Nse "SET @@SESSION.SQL_LOG_BIN=0;ALTER USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
mysql -Nse "SET @@SESSION.SQL_LOG_BIN=0;GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;"
mysql -Nse "SET @@SESSION.SQL_LOG_BIN=0;CREATE USER IF NOT EXISTS 'sstuser'@'localhost';"
mysql -Nse "SET @@SESSION.SQL_LOG_BIN=0;ALTER USER 'sstuser'@'localhost' IDENTIFIED BY '${SSTUSER_PASSWORD}';"
mysql -Nse "SET @@SESSION.SQL_LOG_BIN=0;GRANT RELOAD,PROCESS,LOCK TABLES,REPLICATION CLIENT ON *.* TO 'sstuser'@'localhost';"
mysql -Nse "SET @@SESSION.SQL_LOG_BIN=0;CREATE USER IF NOT EXISTS 'monitor'@'127.0.0.1';"
mysql -Nse "SET @@SESSION.SQL_LOG_BIN=0;ALTER USER 'monitor'@'127.0.0.1' IDENTIFIED BY '${MONITOR_PASSWORD}';"
mysql -Nse "SET @@SESSION.SQL_LOG_BIN=0;GRANT SELECT,CREATE USER,REPLICATION CLIENT,SHOW DATABASES,SUPER,PROCESS,REPLICATION SLAVE ON *.* TO 'monitor'@'127.0.0.1';"
mysql -Nse "SET @@SESSION.SQL_LOG_BIN=0;CREATE USER IF NOT EXISTS 'monitor'@'localhost';"
mysql -Nse "SET @@SESSION.SQL_LOG_BIN=0;ALTER USER 'monitor'@'localhost' IDENTIFIED BY '${MONITOR_PASSWORD}';"
mysql -Nse "SET @@SESSION.SQL_LOG_BIN=0;GRANT SELECT,CREATE USER,REPLICATION CLIENT,SHOW DATABASES,SUPER,PROCESS,REPLICATION SLAVE ON *.* TO 'monitor'@'localhost';"

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

if [ ${GALERA_CLUSTER_UP} -eq 0 ] && [ ${GALERA_NODEID} -eq 0 ]; then
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
