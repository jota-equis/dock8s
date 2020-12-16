#!/usr/bin/env bash

export NODE_ID=$(echo $(hostname) | rev | cut -d- -f1 | rev);

# RESOURCES
export RAM=$(awk '/MemTotal/ {printf( "%d", $2 / 1024 )}' /proc/meminfo)
export RAM_LIMIT=${RAM_LIMIT:-$(($RAM * 75 / 100))}
export CPU_THREADS=$(nproc)
export CPU_LIMIT=${CPU_LIMIT:-$CPU_THREADS};

# MySQL
export MYSQLD="${MYSQLD:-/usr/sbin/mysqld}"
export MYSQL_USER="${MYSQL_USER:-mysql}"
export MYSQL_GROUP="${MYSQL_GROUP:-$MYSQL_USER}"
export MYSQL_UID="${MYSQL_UID:-3306}"
export MYSQL_GID="${MYSQL_GID:-3306}"

export MYSQL_BIND="${MYSQL_BIND:-0.0.0.0}"
export MYSQL_BIND_PORT="${MYSQL_BIND_PORT:-3306}"

export MYSQL_SERVER_ID=$((NODE_ID+1));

export MYSQL_CHARACTER_SET="utf8mb4"
export MYSQL_COLLATE="utf8mb4_unicode_ci"

export MYSQL_ROOT_USER="${MYSQL_ROOT_USER:-root}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"

export MYSQL_HOME="${MYSQL_HOME:-/srv/mysql}"
export MYSQL_FILES="${MYSQL_HOME}/db"
export MYSQL_DATA="${MYSQL_FILES}/data"
export MYSQL_SECURE_DIR="${MYSQL_FILES}/secure"
export MYSQL_CERT_DIR="${MYSQL_FILES}/keyring"
export MYSQL_LOGBIN="${MYSQL_LOGBIN:-$MYSQL_FILES/binlog}"
export MYSQL_BIN="${MYSQL_HOME}/bin"
export MYSQL_LOG="${MYSQL_HOME}/log"
export MYSQL_CONFIG="${MYSQL_HOME}/etc"
export MYSQL_CONFIG_EXTRA="${MYSQL_CONFIG}/mysql.conf.d"
export MYSQL_CNF="${MYSQL_CONFIG}/mysql.cnf"
export MYSQL_TMP="${MYSQL_HOME}/tmp"
export MYSQL_RUN="/run/mysqld"
export MYSQL_PID="${MYSQL_RUN}/mysqld.pid"
export MYSQL_SOCK="${MYSQL_RUN}/mysqld.sock"
export MYSQL_USER_CNF="${MYSQL_HOME}/.my.cnf"

export MYSQL_INNO_BP_SIZE=$((1024 * 1024 * $RAM_LIMIT * 70 / 100))
export MYSQL_INNO_LOG_SIZE=$(($MYSQL_INNO_BP_SIZE * 25 / 100))
export MYSQL_THREADP_SIZE=$(($CPU_LIMIT * 4))

# Daemon
export DAEMON_NAME=mysqld
export DAEMON_BIN="${MYSQLD}"
export DAEMON_HOME="${MYSQL_HOME:-/srv/mysql}"
export DAEMON_FLAGS=""
export DAEMON_FLAGS_EXTRA=""
export DAEMON_FLAGS_FILE="${MYSQL_FILES}/.run_flags"


# GALERA
export GALERA_SERVERID="$(ip a | grep "inet.*eth0" | awk '{print $2}' | cut -d/ -f1 | awk -F. '{printf "%d%s", (($1*256+$2)*256+$3)*256+$4, RT}')"

export GALERA_HOSTPREFIX=$(echo $(hostname) | rev | cut -d- -f2- | rev);

export GALERA_CPU_THREADS=$(($CPU_LIMIT * 3))
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

export GALERA_FC_LIMIT=$(($GALERA_CPU_THREADS * 5))
