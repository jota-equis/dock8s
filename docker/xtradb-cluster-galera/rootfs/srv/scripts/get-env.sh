#!/usr/bin/env bash

export CUR_PID=0
export INIT=-1

export MARIADB_USER="mysql"
export MARIADB_GROUP="mysql"

export MARIADB_PORT="3306"
export MARIADB_BIND="0.0.0.0"

export MARIADB_CHARACTER_SET="utf8mb4"
export MARIADB_COLLATE="utf8mb4_unicode_ci"

export MARIADB_ROOT="/srv/mysql"
export MARIADB_DATA="${MARIADB_ROOT}/data"
export MARIADB_BIN="${MARIADB_ROOT}/bin"
export MARIADB_LOG="${MARIADB_ROOT}/log"
export MARIADB_LOGBIN="${MARIADB_ROOT}/logbin"
export MARIADB_CONFIG="${MARIADB_ROOT}/etc"
export MARIADB_CONFIG_EXTRA="${MARIADB_CONFIG}/my.cnf.d"
export MARIADB_CNF="${MARIADB_CONFIG}/my.cnf"
export MARIADB_SQL="${MARIADB_ROOT}/sql"
export MARIADB_TMP="${MARIADB_ROOT}/tmp"
export MARIADB_RUN="${MARIADB_ROOT}/run"
export MARIADB_PID="${MARIADB_RUN}/mysqld.pid"
export MARIADB_SOCK="${MARIADB_RUN}/mysqld.sock"

export MARIADB_USER_CNF="${MARIADB_ROOT}/.my.cnf"

# RESOURCES
export PATH="${MARIADB_BIN}:${PATH}"
export CPU_THREADS=$(grep -c ^processor /proc/cpuinfo)
export CPU_LIMIT=$((CPU_THREADS/2))
export RAM_MAX=512
export RAM_LIMIT=$((RAM_MAX/4))

# GALERA
export GALERA_SERVERID="$(ip a | grep "inet.*eth0" | awk '{print $2}' | cut -d/ -f1 | awk -F. '{printf "%d%s", (($1*256+$2)*256+$3)*256+$4, RT}')"

export GALERA_GRASTATE="${MARIADB_DATA}/grastate.dat"

export GALERA_BACKUP="${MARIADB_ROOT}/backup"
[[ $CPU_LIMIT -lt 1 ]] && GALERA_BACKUP_THREADS=1 || GALERA_BACKUP_THREADS=$CPU_LIMIT

export GALERA_BOOTSTRAP="${MARIADB_ROOT}/.bootstrap"
export GALERA_BOOTSTRAP_FILE="${GALERA_BOOTSTRAP}/done"
export GALERA_NODE_ADDR=$(hostname -i)

export GALERA_NODENAME=$(hostname);
export GALERA_NODEID=$(echo $(hostname) | rev | cut -d- -f1 | rev);
export GALERA_HOSTPREFIX=$(echo $(hostname) | rev | cut -d- -f2- | rev);

export GALERA_CLUSTER_UP=0

[[ -z "$GALERA_CLUSTER_NAME" ]] && export GALERA_CLUSTER_NAME=$(hostname -f | cut -s -d"." -f2)
[[ -z "$GALERA_CLUSTER_SIZE" ]] && GALERA_CLUSTER_PEERS=2 || GALERA_CLUSTER_PEERS=$((GALERA_CLUSTER_SIZE-1))
[[ -z "$GALERA_CPU_THREADS" ]] && export GALERA_CPU_THREADS=$((CPU_THREADS*4)) || export GALERA_CPU_THREADS="$N"

export GALERA_CLUSTER_ADDR="gcomm://"
export GALERA_SST_METHOD="xtrabackup-v2"

export GALERA_MARIABACKUP_USER="${GALERA_MARIABACKUP_USER:-}"
export GALERA_MARIABACKUP_PASSWORD="${GALERA_MARIABACKUP_PASSWORD:-}"

export GALERA_REPLICATION_USER=""
export GALERA_REPLICATION_PASSWORD=""

