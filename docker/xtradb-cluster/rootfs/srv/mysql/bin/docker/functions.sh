#!/usr/bin/env bash

function setup_node ()
{
    get_peers_up;
    mk_db_install;
    
    MYSQLD_FLAGS="$(get_run_flags)";

    if [[ ! $(is_cluster_up) = 1 && $(is_master_node) = 1 ]]; then
        if [[ -f ${GALERA_GRASTATE} ]]; then
            sed -i "s/^safe_to_bootstrap.*$/safe_to_bootstrap: 1/g" ${GALERA_GRASTATE};
        else
            MYSQLD_FLAGS="${MYSQLD_FLAGS} --wsrep-new-cluster";
        fi
    else
        set_cluster_node_list;
    fi

    set_flags_file;
    fix_ownership;

    logmsg "** Cluster node ${GALERA_HOSTPREFIX}-${GALERA_NODE_ID} bootstraped! **\n";
}

function get_peers_up()
{
    logmsg "Looking for peers.";

    local PEER_STATUS="";
    local PEER_NUMBER=${GALERA_CLUSTER_SIZE:-3};
    local PEER_NAME="";
    local PEER_DNS="";
    local PEER_RUNNING=0;

    for I in $(seq $PEER_NUMBER -1 0); do
        [[ $I = $GALERA_NODE_ID ]] && continue;

        PEER_NAME="${GALERA_HOSTPREFIX}-${I}";
        PEER_DNS="${PEER_NAME}.${GALERA_CLUSTER_NAME}";

        GALERA_CLUSTER_NODES[$I]="${PEER_NAME}";
        
        logmsg "\t... Trying ${PEER_DNS}";
        PEER_STATUS="UNKNOWN";

        if [[ $(getent hosts ${PEER_DNS} | wc -l) = 1 ]]; then
            PEER_STATUS="DOWN";

            if [[ $(nc -w 2 -z ${PEER_DNS} ${MYSQL_PORT} > /dev/null 2>&1) ]]; then
                PEER_STATUS="UP";
                PEER_RUNNING=$((PEER_RUNNING+1));
                GALERA_CLUSTER_UP=1;
            fi
        fi

        logmsg "\t\t... Status: [$PEER_STATUS] ***\n";
    done

    GALERA_CLUSTER_PEERS_UP="${PEER_RUNNING}";

    [[ -f $MYSQL_HOME/.dock8s_has_config_files ]] && logmsg "Keeping previous config files ..." || mk_config;
}

function mk_config ()
{
    logmsg "Make config";

    logmsg "\t... Setting default directory tree.";
    mk_dirs $MYSQL_CONFIG $MYSQL_CONFIG_EXTRA $MYSQL_DATA $MYSQL_BIN $MYSQL_LOG \
    $MYSQL_LOGBIN $MYSQL_SQL $MYSQL_TMP $MYSQL_SECURE_DIR $GALERA_BOOTSTRAP \
    $MYSQL_HOME/mysql-keyring ${MYSQL_CONFIG}/mysql.conf.d ${MYSQL_CONFIG}/conf.d;

    ln -sf $MYSQL_DATA /var/lib/mysql;
    ln -sf $MYSQL_CONFIG /etc/mysql;
    ln -sf $MYSQL_SECURE_DIR /var/lib/;
    ln -sf $MYSQL_HOME/mysql-keyring /var/lib/;

    logmsg "\t... Cleaning up stale config and locks.";
    clean_locks;
    clean_user_conf;

    logmsg "\t... Setting default config files.\n";
    set_file_conf "${MYSQL_CNF}";
    set_file_conf "${MYSQL_CONFIG_EXTRA}/binlog.cnf";
    set_file_conf "${MYSQL_CONFIG_EXTRA}/file.cnf";
    set_file_conf "${MYSQL_CONFIG_EXTRA}/sst.cnf";
    set_file_conf "${MYSQL_CONFIG_EXTRA}/wsrep.cnf";
    set_file_conf "${MYSQL_CONFIG_EXTRA}/xtrabackup.cnf";

    mk_checkpoint $MYSQL_HOME/.dock8s_has_config_files;
}

function mk_db_install ()
{
    local INSTALL_DB=0;
    local DELETE_DB=0;

    if [[ $(is_data_populated) = 1 ]]; then
        [[ ! -f $MYSQL_DATA/.dock8s_has_db_files ]] && DELETE_DB=1;
        # Other cases ...
        # ${GALERA_CLUSTER_PEERS_UP} > 0
    else
        rm_checkpoint $MYSQL_HOME/.dock8s_has_data_files;
        INSTALL_DB=1;
    fi

    db_delete_data $DELETE_DB;
    [[ $INSTALL_DB = 1 || $DELETE_DB = 1 ]] && db_initialize;
}

function db_initialize ()
{
    bak_save_file "${MYSQL_CONFIG_EXTRA}/wsrep.cnf" 1;

    fix_ownership;

	logmsg "\t... Initializing database.";	
	gosu $MYSQL_USER $MYSQLD $(get_run_flags "--initialize-insecure");
	
	mk_checkpoint $MYSQL_DATA/.dock8s_has_db_files;
	
	db_dry_run;

	mk_checkpoint $MYSQL_HOME/.dock8s_has_data_files;

	logmsg "\t... Database initialized.";	
	db_service_stop;

	bak_restore_file "${MYSQL_CONFIG_EXTRA}/wsrep.cnf";
}

function db_dry_run ()
{
    logmsg "\t... Start database service - Dry-run.";

    if [[ $(pgrep -c mysqld) = 0 ]]; then
        ##setsid -f gosu $MYSQL_USER $MYSQLD $(get_run_flags "--log-error=${MYSQL_LOG}/error.log --skip-networking");
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

	logmsg "\t... Connection to database successful - Not using password.";
	
    if [[ -f ${MYSQL_USER_CNF} ]]; then
        logmsg "\t... Connection to database successful - With user config.";
    else
        set_sysusers_password;
        set_root_grants;
        set_system_grants;
    fi
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

    [[ -z $MYSQLD_FLAGS ]] && flags="$(get_default_flags)";
    
    for f in "${@}"; do
        flags="${flags} ${f}";
    done
    
    echo "${flags}";
}

function set_flags_file ()
{
    [[ ! -z "${MYSQLD_FLAGS}" ]] && echo "${MYSQLD_FLAGS}" > ${MYSQL_HOME}/.run_flags;
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
    if [[ ! -z ${GALERA_CLUSTER_NODES} ]]; then
        printf -v GALERA_CLUSTER_NODE_LIST '%s,' "${GALERA_CLUSTER_NODES[@]}";

        [[ ! -z ${GALERA_CLUSTER_NODE_LIST} ]] && \
            sed -i "s|^wsrep_cluster_address.*$|wsrep_cluster_address = gcomm://$(echo "${GALERA_CLUSTER_NODE_LIST%,}")|g" \
            ${MYSQL_CONFIG_EXTRA}/wsrep.cnf;
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
    local F="${1:-}"
    [[ -f "${F}" ]] && rm -f "${F}" > /dev/null 2>&1;
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
	rm_checkpoint $MYSQL_HOME/.dock8s_has_data_files;
}

function set_boot_envs ()
{
    for E in "${@}"; do
        [[ ! -z "${E}" ]] && BOOTFLAGS+=("${E}");
    done
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

function is_master_node ()
{
    [[ -z "$GALERA_NODE_ID" ]] && export GALERA_NODE_ID=$(echo $(hostname) | rev | cut -d- -f1 | rev);
    [[ $GALERA_NODE_ID = 0 ]] && echo 1 || echo 0;
}

function is_data_populated ()
{
    [[ -d "$MYSQL_DATA/mysql" ]] && echo 1 || echo 0;
}

function is_cluster_up ()
{
    [[ -z "$GALERA_CLUSTER_UP" ]] && export GALERA_CLUSTER_UP=0;
    [[ $GALERA_CLUSTER_UP = 1 ]] && echo 1 || echo 0;
}


###########

function __term_handler ()
{
    local L="${!}";
    local P="${1:-${CUR_PID:-$L}}";
    
    CUR_PID="${P:-0}";

    if [[ ! $CUR_PID = 0 ]]; then
        logmsg "Stop trapped, draining users"
        touch /tmp/drain.lock

        if [ $(mysql --defaults-file=${MYSQL_USER_CNF} -Nse "SELECT 1;" 2>/dev/null) ]; then
            CONNS=$(mysql --defaults-file=${MYSQL_USER_CNF} -Nse "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE User NOT IN ('root','system user','sstuser','monitor');" 2>/dev/null )
            
            START=$(date +%s)
            NOW=$(date +%s)
            
            while [ ${CONNS} -gt 0 ]; do
                for con in $(mysql --defaults-file=${MYSQL_USER_CNF} -Nse "SELECT ID FROM information_schema.PROCESSLIST WHERE User NOT IN ('root','system user','sstuser','monitor');" 2>/dev/null ); do
                
                    if [ "$(mysql --defaults-file=${MYSQL_USER_CNF} -Nse "SELECT IF(COMMAND='Sleep',1,0) FROM information_schema.PROCESSLIST WHERE ID=$con;" 2>/dev/null )" = "1" ]; then
                        mysql --defaults-file=${MYSQL_USER_CNF} -Nse "KILL CONNECTION $con;" 2>/dev/null
                    fi
                done

                CONNS=$(mysql --defaults-file=${MYSQL_USER_CNF} -Nse "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE User NOT IN ('root','system user','sstuser','monitor');" 2>/dev/null )

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




