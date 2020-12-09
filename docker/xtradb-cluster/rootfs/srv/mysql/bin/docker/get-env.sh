#!/usr/bin/env bash

export BOOTARGS=""
export BOOTFLAGS=()
export CUR_PID=0
export CUR_STATUS=-1

export NODE_ID=$(echo $(hostname) | rev | cut -d- -f1 | rev);

export MYSQL_USER="mysql"
export MYSQL_GROUP="mysql"
export MYSQL_UID="3306"
export MYSQL_GID="3306"

export MYSQLD=/usr/sbin/mysqld

export MYSQL_PORT="3306"
export MYSQL_BIND="0.0.0.0"

export MYSQL_SERVER_ID=$((NODE_ID+1));

export MYSQL_CHARACTER_SET="utf8mb4"
export MYSQL_COLLATE="utf8mb4_unicode_ci"

export MYSQL_ROOT_USER="${MYSQL_ROOT_USER:-root}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"

export MYSQL_HOME="/srv/mysql"
export MYSQL_DATA="${MYSQL_HOME}/data"
export MYSQL_SECURE_DIR="${MYSQL_HOME}/mysql-files"
export MYSQL_BIN="${MYSQL_HOME}/bin"
export MYSQL_LOG="${MYSQL_HOME}/log"
export MYSQL_LOGBIN="${MYSQL_HOME}/logbin"
export MYSQL_CONFIG="${MYSQL_HOME}/etc"
export MYSQL_CONFIG_EXTRA="${MYSQL_CONFIG}/my.cnf.d"
export MYSQL_CNF="${MYSQL_CONFIG}/mysql.cnf"
export MYSQL_SQL="${MYSQL_HOME}/sql"
export MYSQL_TMP="${MYSQL_HOME}/tmp"
export MYSQL_RUN="/run/mysqld"
export MYSQL_PID="${MYSQL_RUN}/mysqld.pid"
export MYSQL_SOCK="${MYSQL_RUN}/mysqld.sock"

export MYSQL_USER_CNF="${MYSQL_HOME}/.my.cnf"

export MYSQLD_FLAGS=""
export MYSQLD_FLAGS_FILE="$MYSQL_HOME/.dock8s_run_flags"

# RESOURCES
export PATH="${MYSQL_BIN}:${PATH}"
export CPU_THREADS=$(grep -c ^processor /proc/cpuinfo)
export CPU_LIMIT="${CPU_LIMIT:-$((CPU_THREADS/2))}"
export RAM_MAX="${RAM_MAX:-512}"
export RAM_LIMIT="${RAM_LIMIT:-$((RAM_MAX/4))}"

# GALERA
export GALERA_SERVERID="$(ip a | grep "inet.*eth0" | awk '{print $2}' | cut -d/ -f1 | awk -F. '{printf "%d%s", (($1*256+$2)*256+$3)*256+$4, RT}')"

export GALERA_HOSTPREFIX=$(echo $(hostname) | rev | cut -d- -f2- | rev);

export GALERA_CPU_THREADS="${GALERA_CPU_THREADS:-$((CPU_THREADS*2))}"
export GALERA_BACKUP_THREADS="${GALERA_BACKUP_THREADS:-$((CPU_LIMIT-1))}"
[[ $GALERA_BACKUP_THREADS < 1 ]] && export GALERA_BACKUP_THREADS=1

export GALERA_BOOTSTRAP="${MYSQL_HOME}/.bootstrap"
export GALERA_BOOTSTRAP_FILE="${GALERA_BOOTSTRAP}/done"

export GALERA_NODE_ADDR=$(hostname -i)
export GALERA_NODE_NAME=${GALERA_NODE_NAME:-${MY_POD_NAME:-$(hostname)}};
export GALERA_NODE_ID=$NODE_ID;

export GALERA_CLUSTER_UP=0
export GALERA_CLUSTER_PEERS_UP=0
export GALERA_CLUSTER_NAME="${GALERA_CLUSTER_NAME:-$(hostname -f | cut -s -d"." -f2)}"
export GALERA_CLUSTER_SIZE="${GALERA_CLUSTER_SIZE:-3}"
export GALERA_CLUSTER_ADDR="${GALERA_CLUSTER_ADDR:-${GALERA_CLUSTER_NAME:-$(hostname -d)}}"
export GALERA_CLUSTER_NODES=()
export GALERA_CLUSTER_NODE_LIST=""

export GALERA_GRASTATE="${MYSQL_DATA}/grastate.dat"
export GALERA_SST_METHOD="xtrabackup-v2"

export GALERA_MARIABACKUP_USER="${GALERA_MARIABACKUP_USER:-galera-backup}"
export GALERA_MARIABACKUP_PASSWORD="${GALERA_MARIABACKUP_PASSWORD:-}"

export GALERA_REPLICATION_USER="${GALERA_REPLICATION_USER:-xtrabackup}"
export GALERA_REPLICATION_PASSWORD="${GALERA_REPLICATION_PASSWORD:-}"

export GALERA_MONITOR_USER="${GALERA_MONITOR_USER:-monitor}"
export GALERA_MONITOR_PASSWORD="${GALERA_MONITOR_PASSWORD:-}"

export GALERA_CLUSTERCHECK_USER="${GALERA_CLUSTERCHECK_USER:-clustercheck}"
export GALERA_CLUSTERCHECK_PASSWORD="${GALERA_CLUSTERCHECK_PASSWORD:-}"
