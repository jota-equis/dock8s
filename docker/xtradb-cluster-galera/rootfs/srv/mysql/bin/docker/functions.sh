#!/usr/bin/env bash

function mk_config ()
{
    logmsg "Make config";
    logmsg "\t... Setting default directory tree.";

    mk_dirs $MARIADB_CONFIG_EXTRA $MARIADB_DATA $MARIADB_BIN $MARIADB_LOG \
    $MARIADB_LOGBIN $MARIADB_SQL $MARIADB_TMP $GALERA_BACKUP $GALERA_BOOTSTRAP;

    logmsg "\t... Cleaning up stale config and locks.";

    clean_locks;
    clean_user_conf;
    [[ -f ${MARIADB_DATA}/sst_in_progress ]] && rm -f "${MARIADB_DATA}/sst_in_progress";

    logmsg "\t... Setting default config files.";

    set_file_conf "${MARIADB_CONFIG}/my.cnf";
    set_file_conf "${MARIADB_CONFIG_EXTRA}/binlog.cnf";
    set_file_conf "${MARIADB_CONFIG_EXTRA}/wsrep.cnf";
    set_file_conf "${MARIADB_CONFIG_EXTRA}/sst.cnf";
    set_file_conf "${MARIADB_CONFIG_EXTRA}/xtrabackup.cnf";

    [[ -d "${GALERA_BACKUP}" ]] && set_file_conf "${MARIADB_CONFIG_EXTRA}/file.cnf";
    
    echo "";
}

function init_config ()
{
    mk_config;

    logmsg "Looking for peers.";

    local S="";
    local N=$GALERA_CLUSTER_PEERS
    export GALERA_CLUSTER_UP=0

    until [[ $N < 0 ]]; do
        [[ $N = $GALERA_NODE_ID ]] && { N=$((N-1)); continue; };

        logmsg "\t... Trying ${GALERA_HOSTPREFIX}-${N}.${GALERA_CLUSTER_NAME}";
        S="UNKNOWN";

        if [[ $(getent hosts ${GALERA_HOSTPREFIX}-${N}.${GALERA_CLUSTER_NAME} | wc -l) = 1 ]]; then
            S="DOWN";

            $(nc -w 2 -z ${GALERA_HOSTPREFIX}-${N}.${GALERA_CLUSTER_NAME} ${MARIADB_PORT} > /dev/null 2>&1) && { S="UP"; GALERA_CLUSTER_UP=1; };
        fi

        logmsg "\t... Status: [$S] ***";

        N=$((N-1))
    done

    echo "";
    S=-1

    if [[ ! $(is_data_populated) = 1 ]]; then
        bak_save_file "${MARIADB_CONFIG_EXTRA}/wsrep.cnf";
        db_initialize;

        logmsg "\t... Finishing node bootstrapping.";
        killall mysqld && until [ $(pgrep -c mysqld) -eq 0 ]; do sleep 1; done

        bak_restore_file "${MARIADB_CONFIG_EXTRA}/wsrep.cnf";

        logmsg "\t... Node initialization done.";
        logmsg "\t... MySQL shutdown.";
    fi

    if [[ ! $(is_cluster_up) = 1 && $(is_master_node) = 1 ]]; then
        [[ -f ${GALERA_GRASTATE} ]] && sed -i "s/^safe_to_bootstrap.*$/safe_to_bootstrap: 1/g" ${GALERA_GRASTATE}
        BOOTARGS="--wsrep-new-cluster"
    fi

    logmsg "\n** XtraDB setup finished! **\n";
    set_boot_envs BOOTARGS MARIADB_CNF MARIADB_DATA MARIADB_USER
}

function term_handler ()
{
    local L="${!}";
    local P="${1:-${CUR_PID:-$L}}";
    
    CUR_PID="${P:-0}";

    if [[ ! $CUR_PID = 0 ]]; then
        logmsg "Stop trapped, draining users"
        touch /tmp/drain.lock

        if [ $(mysql --defaults-file=${MARIADB_USER_CNF} -Nse "SELECT 1;" 2>/dev/null) ]; then
            CONNS=$(mysql --defaults-file=${MARIADB_USER_CNF} -Nse "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE User NOT IN ('root','system user','sstuser','monitor');" 2>/dev/null )
            
            START=$(date +%s)
            NOW=$(date +%s)
            
            while [ ${CONNS} -gt 0 ]; do
                for con in $(mysql --defaults-file=${MARIADB_USER_CNF} -Nse "SELECT ID FROM information_schema.PROCESSLIST WHERE User NOT IN ('root','system user','sstuser','monitor');" 2>/dev/null ); do
                
                    if [ "$(mysql --defaults-file=${MARIADB_USER_CNF} -Nse "SELECT IF(COMMAND='Sleep',1,0) FROM information_schema.PROCESSLIST WHERE ID=$con;" 2>/dev/null )" = "1" ]; then
                        mysql --defaults-file=${MARIADB_USER_CNF} -Nse "KILL CONNECTION $con;" 2>/dev/null
                    fi
                done

                CONNS=$(mysql --defaults-file=${MARIADB_USER_CNF} -Nse "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE User NOT IN ('root','system user','sstuser','monitor');" 2>/dev/null )

                logmsg "Connected users: ${CONNS}"

                NOW=$(date +%s)

                [[ $NOW -gt $((START+60)) ]] && break
            done
        fi

        logmsg "60 seconds has elapsed - forcing users off";
        
        mysql -Nse "SET GLOBAL wsrep_reject_queries=ALL_KILL;"

        kill "$CUR_PID"
        wait "$CUR_PID"
    fi

    exit 0;
}

function get_root_grant_query ()
{
    local Q="GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' IDENTIFIED BY '$MARIADB_ROOT_PASSWORD' WITH GRANT OPTION;";
    echo "SET @@SESSION.SQL_LOG_BIN=0;$Q";
}

function setup_users ()
{
    set_sysusers_password;

    logmsg "\t... Setting up system users and securing defaults.";

    $(mysql -Ns << EOF
SET @@SESSION.SQL_LOG_BIN=0;

GRANT RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT \
  ON *.* TO 'xtrabackup'@'localhost' IDENTIFIED BY '$GALERA_REPLICATION_PASSWORD';

GRANT SELECT, CREATE USER, REPLICATION CLIENT, SHOW DATABASES, SUPER, PROCESS, REPLICATION SLAVE \
  ON *.* TO 'monitor'@'localhost' IDENTIFIED BY '${GALERA_MONITOR_PASSWORD}';

GRANT SELECT, CREATE USER, REPLICATION CLIENT, SHOW DATABASES, SUPER, PROCESS, REPLICATION SLAVE \
  ON *.* TO 'monitor'@'127.0.0.1' IDENTIFIED BY '${GALERA_MONITOR_PASSWORD}';

GRANT USAGE \
  ON *.* TO 'clustercheck'@'localhost' IDENTIFIED BY '$GALERA_CLUSTERCHECK_PASSWORD';

DELETE FROM mysql.user WHERE User='';

DROP DATABASE IF EXISTS test;

DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';

FLUSH PRIVILEGES;
EOF
    ) > /dev/null 2>&1
}

function db_initialize ()
{
	logmsg "\t... Initializing database.";

	db_delete_data 1;

	mysqld --defaults-file=${MARIADB_CNF} \
        --datadir=${MARIADB_DATA} \
        --user=${MARIADB_USER} \
        --initialize-insecure;

	db_initialize_check;
	write_user_conf;
	
	setup_users;
}

function db_initialize_check ()
{
	mysqld --defaults-file=${MARIADB_CNF} \
		--datadir=${MARIADB_DATA} \
		--user=${MARIADB_USER} \
		--log-error=${MARIADB_LOG}/mysqld.log \
		--skip-networking &

	for I in {1..30}; do
		$(mysql -u root -S ${MARIADB_SOCK} -Nse "SELECT 1;" > /dev/null 2>&1) && break || sleep 2;
	done

	[[ ${I} -eq 30 ]] && logerror "Failed to initialize database!\n";

	$(mysql -S ${MARIADB_SOCK} -u root -Nse "$(get_root_grant_query)" 2>/dev/null) || logerror "Failed to initialize root password!\n";
}

function write_user_conf ()
{
    logmsg "\t... Setting user cnf.";

    set_file_conf "${MARIADB_USER_CNF}";
    chmod 0640 ${MARIADB_USER_CNF};
}

# Utility
function logmsg ()
{
    local MSG="${1:-Undefined}";
    local LEVEL=${2:-0}
    local MODE;
    
    [[ $LEVEL -eq 0 ]] && MODE="Info" || MODE="Error";

    echo -e "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") $LEVEL [$MODE] $MSG";
}

function logerror ()
{
    local MSG="${1:-Undefined}";
    local KEEP="${2:-0}";
    
    logmsg "$MSG" 1;

    [[ $KEEP -eq 0 ]] && exit 1;
}

function mk_dirs ()
{
    for D in "${@}"; do
        [[ ! -d "${D}" ]] && mkdir -pm0750 ${D};
    done
}

function set_file_conf ()
{
    local F="${1:-}"
    [[ -f "${F}.default" ]] && { envsubst < "${F}.default" > "${F}"; rm -f "${F}.default"; };
}

function clean_locks ()
{
    [[ -f "${MARIADB_SOCK}.lock" ]] && rm -f "${MARIADB_SOCK}.lock";
}

function clean_user_conf ()
{
    [[ -f "${MARIADB_USER_CNF}" ]] && rm -f "${MARIADB_USER_CNF}";
}

function bak_save_file ()
{
    local F="${1:-}";
    [[ -f "${F}" ]] && cp -afx "${F}" "${F}.bak";
}

function bak_restore_file ()
{
    local F="${1:-}";
    [[ -f "${F}.bak" ]] && mv "${F}.bak" "${F}";
}

function db_delete_data ()
{
	[[ ${1:-0} = 1 ]] && rm -Rf ${MARIADB_DATA}/*;
}

function set_boot_envs ()
{
    local F=${MARIADB_BOOTARGS_FILE}

    [[ -f ${F} ]] && rm -f ${F};

    for E in "${@}"; do
        [[ ! -z "${E}" ]] && echo "${E}=${!E}" >> ${F};
    done
}

function get_boot_envs ()
{
    local F=${MARIADB_BOOTARGS_FILE}
    [[ -f ${F} ]] && { . ${F}; rm -f ${F}; };
}

function get_rnd_password ()
{
    echo "$(openssl rand -base64 16)";
}

function set_sysusers_password ()
{
    [[ -z $MARIADB_ROOT_PASSWORD ]] && export MARIADB_ROOT_PASSWORD="$(get_rnd_password)";
    [[ -z $GALERA_MARIABACKUP_PASSWORD ]] && export GALERA_MARIABACKUP_PASSWORD="$(get_rnd_password)";
    [[ -z $GALERA_REPLICATION_PASSWORD ]] && export GALERA_REPLICATION_PASSWORD="$(get_rnd_password)";
    [[ -z $GALERA_MONITOR_PASSWORD ]] && export GALERA_MONITOR_PASSWORD="$(get_rnd_password)";
    [[ -z $GALERA_CLUSTERCHECK_PASSWORD ]] && export GALERA_CLUSTERCHECK_PASSWORD="$(get_rnd_password)";
}

function is_master_node ()
{
    [[ -z "$GALERA_NODE_ID" ]] && export GALERA_NODE_ID=$(echo $(hostname) | rev | cut -d- -f1 | rev);
    [[ $GALERA_NODE_ID = 0 ]] && echo 1 || echo 0;
}

function is_data_populated ()
{
    [[ -d "$MARIADB_DATA/mysql" ]] && echo 1 || echo 0;
}

function is_cluster_up ()
{
    [[ -z "$GALERA_CLUSTER_UP" ]] && export GALERA_CLUSTER_UP=0;
    [[ $GALERA_CLUSTER_UP = 1 ]] && echo 1 || echo 0;
}
