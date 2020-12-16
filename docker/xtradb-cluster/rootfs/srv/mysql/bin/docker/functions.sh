#!/usr/bin/env bash

function setup_node ()
{
    is_service_up && return || get_peers_up;

    DAEMON_FLAGS="$(get_run_flags)";
    INSTALL_DB=0

    if ! is_cluster_up; then
        logmsg "** No running cluster found.";
        
        if ! is_data_populated; then
            logmsg "** No previous data found.";
            INSTALL_DB=1;
            DAEMON_FLAGS_EXTRA="--wsrep-new-cluster";
        else
            logmsg "** Previous data found!";
            sed -i "s/^safe_to_bootstrap.*$/safe_to_bootstrap: 1/g" ${GALERA_GRASTATE};
        fi
    else
        logmsg "** There is a running cluster!";
        INSTALL_DB=1;
    fi
    
    [[ -f $MYSQL_CNF ]] && logmsg "Keeping previous config files ..." || mk_config;

    bak_save_file "${MYSQL_CONFIG_EXTRA}/wsrep.cnf" "mv";
    
    if [[ $INSTALL_DB = 1 ]]; then
        db_delete_data 1;
        db_initialize;
    else
        db_dry_run;
    fi
    
    bak_restore_file "${MYSQL_CONFIG_EXTRA}/wsrep.cnf";

    logmsg "** Cluster node ${GALERA_HOSTPREFIX}-${GALERA_NODE_ID} bootstraped! **\n";
    unset_vars;
}

function get_peers_up()
{
    logmsg "Looking for peers.";

    local PEER_STATUS="";
    local PEER_NAME="";
    local PEER_DNS="";
    local PEER_RUNNING=0;

    for I in $(seq $((${GALERA_CLUSTER_SIZE:-3} - 1)) -1 0); do
        [[ $I = $GALERA_NODE_ID ]] && continue;

        PEER_NAME="${GALERA_HOSTPREFIX}-${I}";
        PEER_DNS="${PEER_NAME}.${GALERA_CLUSTER_NAME}";

        GALERA_CLUSTER_NODES[$I]="${PEER_NAME}";
        
        logmsg "\t... Trying ${PEER_DNS}";
        PEER_STATUS="UNKNOWN";

        if is_host ${PEER_DNS}; then
            PEER_STATUS="DOWN";

            if is_listening ${PEER_DNS} ${MYSQL_BIND_PORT}; then
                PEER_STATUS="UP";
                PEER_RUNNING=$((PEER_RUNNING+1));
            fi
        fi

        logmsg "\t\t... Status: [$PEER_STATUS] ***\n";
    done

    GALERA_CLUSTER_PEERS_UP="${PEER_RUNNING}";
}

function mk_config ()
{
    logmsg "Make config";

    logmsg "\t... Setting default directory tree.";
    mk_dirs $MYSQL_FILES $MYSQL_DATA $MYSQL_SECURE_DIR $MYSQL_CERT_DIR \
    $MYSQL_LOGBIN $MYSQL_BIN $MYSQL_LOG $MYSQL_CONFIG $MYSQL_TMP \
    $MYSQL_CONFIG_EXTRA;

    ln -sf $MYSQL_DATA /var/lib/mysql;
    ln -sf $MYSQL_SECURE_DIR /var/lib/mysql-files;
    ln -sf $MYSQL_CERT_DIR /var/lib/mysql-keyring;

    logmsg "\t... Cleaning up stale config and locks.";
    clean_locks;
    clean_user_conf;

    logmsg "\t... Setting default config files.\n";
    set_file_conf "${MYSQL_CNF}";
    set_file_conf "${MYSQL_CONFIG_EXTRA}/binlog.cnf";
    set_file_conf "${MYSQL_CONFIG_EXTRA}/sst.cnf";
    set_file_conf "${MYSQL_CONFIG_EXTRA}/wsrep.cnf";
    set_file_conf "${MYSQL_CONFIG_EXTRA}/xtrabackup.cnf";
}

function db_initialize ()
{
	logmsg "\t... Initializing database.";	
	gosu $MYSQL_USER $MYSQLD $(get_run_flags "--initialize-insecure");
	
	mk_checkpoint $MYSQL_DATA/.dock8s_has_db_files;
	
	db_dry_run;
}

function db_dry_run ()
{
    logmsg "\t... Start database service - Dry-run.";

    if [[ $(pgrep -c mysqld) = 0 ]]; then
        gosu $MYSQL_USER $MYSQLD $(get_run_flags "--log-error=${MYSQL_LOG}/error.log --skip-networking") &
    else
        logmsg "\t\t... Database service already started - Dry-run.";
    fi

    db_connection_test;
}

function db_connection_test ()
{
    logmsg "\t... Checking if server is listening.";
    local SUCCESS=0;
    local TEST_LOG;
    local PARAMS="";

    [[ -f ${MYSQL_USER_CNF} ]] && PARAMS="--defaults-file=$MYSQL_USER_CNF";

	for I in {1..60}; do
        TEST_LOG="\t\t... Waiting for service PID & Socket - $I/60";

        if [[ -f ${MYSQL_PID} && 0 < $(<"${MYSQL_PID}") && -S ${MYSQL_SOCK} ]]; then
            TEST_LOG="$TEST_LOG ... Trying to connect";
            $(mysql ${PARAMS} -Nse "SELECT 1;" > /dev/null 2>&1) && { SUCCESS=1; logmsg "${TEST_LOG} - OK!"; break; };
        fi

        logmsg "$TEST_LOG";
        sleep 1;
	done

	if [[ $SUCCESS = 0 ]]; then
        TEST_LOG="\t... Connection to database failed -";
        [[ ! -f ${MYSQL_USER_CNF} ]] && logerror "$TEST_LOG Not using password.";

        logmsg "$TEST_LOG With user config.";
        clean_user_conf;
        db_connection_test;
        return 0;
	fi

    if [[ -f ${MYSQL_USER_CNF} ]]; then
        logmsg "\t... Connection to database successful - With user config.";
    else
        logmsg "\t... Connection to database successful - Not using password.";
        set_sysusers_password;
        set_root_grants;
        set_system_grants;
    fi
    
    logmsg "\t... Database initialized.";
    db_service_stop;
}

function db_service_stop ()
{
    logmsg "\t... Stopping database service.";
    [[ ! $(pgrep -c mysqld) = 0 ]] && { killall mysqld && until [[ $(pgrep -c mysqld) = 0 ]]; do sleep 1; done }

    logmsg "\t\t... Stopped.";
}

function fix_ownership ()
{
    local T="${1:-$MYSQL_HOME/*}";
    [[ -d "${T}" || -f "${T}" ]] && chown -R "${MYSQL_USER}":"${MYSQL_USER}" ${T} > /dev/null 2>&1;
}

function mk_checkpoint ()
{
    local f="${1:-}";
    [[ -z "${f}" ]] || { touch "${f}"; fix_ownership "${f}"; };
}

function rm_checkpoint ()
{
    [[ -z "${1:-}" ]] || del_file "${1:-}";
}

function get_run_flags ()
{
    local flags="";

    [[ -z $DAEMON_FLAGS ]] && flags="$(get_default_flags)";
    
    for f in "${@}"; do
        flags="${flags} ${f}";
    done
    
    echo "${flags}";
}

function set_flags_file ()
{
    [[ ! -z "${DAEMON_FLAGS}" ]] && echo "${DAEMON_FLAGS}" > $DAEMON_FLAGS_FILE;
}

function get_default_flags ()
{
    echo "--defaults-file=${MYSQL_CNF} --datadir=${MYSQL_DATA} --user=${MYSQL_USER}";
    # --socket=${MYSQL_SOCK} --pid-file=${MYSQL_PID}";
}

function set_root_grants ()
{
    logmsg "\t... Updating mysql root password.";
    
    local Q;
    read -r -d '' Q <<EOF
        SET @@SESSION.SQL_LOG_BIN=0;
        CREATE USER IF NOT EXISTS 'root'@'localhost';
        ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
        GRANT ALL ON *.* TO 'root'@'localhost';
        CREATE USER IF NOT EXISTS 'root'@'127.0.0.1';
        ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
        GRANT ALL ON *.* TO 'root'@'127.0.0.1';
        FLUSH PRIVILEGES;
EOF
    $(mysql -Nse "$Q") > /dev/null 2>&1 || logerror "\t... Failed to update database root password!\n";

    write_user_conf;
}

function set_system_grants ()
{
    logmsg "\t... Setting up system users and securing defaults.";

    local Q;
    read -r -d '' Q <<EOF
        SET @@SESSION.SQL_LOG_BIN=0;

        CREATE USER IF NOT EXISTS 'xtrabackup'@'localhost' IDENTIFIED BY '$GALERA_REPLICATION_PASSWORD';
        GRANT RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT ON *.* TO 'xtrabackup'@'localhost';

        CREATE USER IF NOT EXISTS 'xtrabackup'@'127.0.0.1' IDENTIFIED BY '$GALERA_REPLICATION_PASSWORD';
        GRANT RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT ON *.* TO 'xtrabackup'@'127.0.0.1';

        CREATE USER IF NOT EXISTS 'monitor'@'localhost' IDENTIFIED BY '$GALERA_MONITOR_PASSWORD';
        GRANT SELECT, CREATE USER, REPLICATION CLIENT, SHOW DATABASES, SUPER, PROCESS, REPLICATION SLAVE \
        ON *.* TO 'monitor'@'localhost';

        CREATE USER IF NOT EXISTS 'monitor'@'127.0.0.1' IDENTIFIED BY '$GALERA_MONITOR_PASSWORD';
        GRANT SELECT, CREATE USER, REPLICATION CLIENT, SHOW DATABASES, SUPER, PROCESS, REPLICATION SLAVE \
        ON *.* TO 'monitor'@'127.0.0.1';

        CREATE USER IF NOT EXISTS 'clustercheck'@'localhost' IDENTIFIED BY '$GALERA_CLUSTERCHECK_PASSWORD';
        GRANT USAGE ON *.* TO 'clustercheck'@'localhost';

        CREATE USER IF NOT EXISTS 'clustercheck'@'127.0.0.1' IDENTIFIED BY '$GALERA_CLUSTERCHECK_PASSWORD';
        GRANT USAGE ON *.* TO 'clustercheck'@'127.0.0.1';

        DELETE FROM mysql.user WHERE User='';
        DROP DATABASE IF EXISTS test;
        DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';

        FLUSH PRIVILEGES;
EOF

    $(mysql --defaults-file=${MYSQL_USER_CNF} -Nse "$Q") > /dev/null 2>&1  || logerror "\t... Failed setting up system users and securing defaults\n";
}

function set_cluster_node_list ()
{
    if [[ ! -z ${GALERA_CLUSTER_ADDR} ]]; then
        sed -i "s|^wsrep_cluster_address.*$|wsrep_cluster_address = gcomm://${GALERA_CLUSTER_ADDR}|g" \
            ${MYSQL_CONFIG_EXTRA}/wsrep.cnf;
    else
        if [[ ! -z ${GALERA_CLUSTER_NODES} ]]; then
            printf -v GALERA_CLUSTER_NODE_LIST '%s,' "${GALERA_CLUSTER_NODES[@]}";

            [[ ! -z ${GALERA_CLUSTER_NODE_LIST} ]] && \
                sed -i "s|^wsrep_cluster_address.*$|wsrep_cluster_address = gcomm://$(echo "${GALERA_CLUSTER_NODE_LIST%,}")|g" \
                ${MYSQL_CONFIG_EXTRA}/wsrep.cnf;
        fi
    fi
}

function write_user_conf ()
{
    logmsg "\t... Writting user config.";
    set_file_conf "${MYSQL_USER_CNF}";
}

# Utility
function logmsg ()
{
    local MSG="${1:-Undefined}";
    local LEVEL=${2:-0}
    local MODE;
    
    [[ $LEVEL = 0 ]] && MODE="Info" || MODE="Error";

    echo -e "$(date +'%Y-%m-%dT%H:%M:%S.%6NZ') $LEVEL [$MODE] $MSG";
}

function logerror ()
{
    local MSG="${1:-Undefined}";
    local KEEP="${2:-0}";
    
    logmsg "$MSG" 1;

    [[ $KEEP = 0 ]] && exit 1;
}

function mk_dirs ()
{
    for d in "${@}"; do
        if [[ ! -d "${d}" ]]; then
            logmsg "\t\t... Create directory: ${d}";
            mkdir -pm0750 ${d};
        fi
        
        fix_ownership "${d}";
    done
}

function set_file_conf ()
{
    local F="${1:-}";

    if [[ -f "${F}.default" ]]; then
        envsubst < "${F}.default" > "${F}";
        del_file ${F}.default;
    fi

    chmod 0640 "${F}";
    fix_ownership "${F}";
}

function del_file ()
{
    [[ ! -z "${1:-}" ]] && [[ -f "${1}" ]] && rm -f "${1}" > /dev/null 2>&1;
}

function clean_locks ()
{
    del_file "${MYSQL_SOCK}.lock";
    del_file "${MYSQL_DATA}/sst_in_progress";
}

function clean_user_conf ()
{
    del_file "${MYSQL_USER_CNF}";
}

function bak_save_file ()
{
    local F="${1:-}";
    [[ -f "${F}" ]] && [[ -z "${2:-}" ]] && cp -afx "${F}" "${F}.bak" || mv -f "${F}" "${F}.bak";
}

function bak_restore_file ()
{
    local F="${1:-}";
    [[ -f "${F}.bak" ]] && mv "${F}.bak" "${F}";
}

function db_delete_data ()
{
	[[ ${1:-0} = 1 ]] && rm -Rf ${MYSQL_DATA}/*;
}

function get_rnd_password ()
{
    echo "$(openssl rand -base64 16)";
}

function set_sysusers_password ()
{
    [[ -z $MYSQL_ROOT_PASSWORD ]] && export MYSQL_ROOT_PASSWORD="$(get_rnd_password)";
    [[ -z $GALERA_MARIABACKUP_PASSWORD ]] && export GALERA_MARIABACKUP_PASSWORD="$(get_rnd_password)";
    [[ -z $GALERA_REPLICATION_PASSWORD ]] && export GALERA_REPLICATION_PASSWORD="$(get_rnd_password)";
    [[ -z $GALERA_MONITOR_PASSWORD ]] && export GALERA_MONITOR_PASSWORD="$(get_rnd_password)";
    [[ -z $GALERA_CLUSTERCHECK_PASSWORD ]] && export GALERA_CLUSTERCHECK_PASSWORD="$(get_rnd_password)";
}

function unset_vars ()
{
    unset MY_POD_NAME MYSQL_ROOT_PASSWORD _;
}

function is_data_populated ()
{
    [[ -d $MYSQL_DATA && -d "$MYSQL_DATA/mysql" && -f ${GALERA_GRASTATE} && -f $MYSQL_DATA/.dock8s_has_db_files ]] && return;
    false;
}

function is_configured ()
{
    [[ -f $MYSQL_CNF ]] && return;
    false;
}

function is_host ()
{
    [[ ! -z "${1:-}" ]] && [[ $(getent hosts $1 | wc -l) > 0 ]] && return;
    false;
}

function is_cluster_up ()
{
    is_host ${GALERA_CLUSTER_NAME} && { export GALERA_CLUSTER_UP=1; return; }
    false;
}

function is_listening ()
{
    is_host "${1:-}" && [[ ! -z "${2:-}" ]] && $(nc -w 2 -z $1 $2) && return;
    false;
}

function is_service_up ()
{
    $(mysql -Nse "SELECT 1;" > /dev/null 2>&1) && return;
    false;
}

function is_daemon_running ()
{
    [[ $(pgrep -c $DAEMON_NAME) != 0 ]] && return;
    false;
}
