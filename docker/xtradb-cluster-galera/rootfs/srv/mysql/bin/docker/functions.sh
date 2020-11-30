#!/usr/bin/env bash

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

function mk_appdir ()
{
    logmsg "Setting default directory tree";

    mkdir -pm0750 $MARIADB_CONFIG_EXTRA $MARIADB_DATA $MARIADB_BIN $MARIADB_LOG \
    $MARIADB_LOGBIN $MARIADB_SQL $MARIADB_TMP $GALERA_BACKUP $GALERA_BOOTSTRAP;

    clean_prev;
}

function mk_newconf ()
{
    mk_appdir;

    logmsg "Setting initial default config";

    set_file_conf "${MARIADB_CONFIG}/my.cnf";
    set_file_conf "${MARIADB_CONFIG_EXTRA}/binlog.cnf";
    set_file_conf "${MARIADB_CONFIG_EXTRA}/wsrep.cnf";
    set_file_conf "${MARIADB_CONFIG_EXTRA}/sst.cnf";
    set_file_conf "${MARIADB_CONFIG_EXTRA}/xtrabackup.cnf";

    [[ -d "${GALERA_BACKUP}" ]] && set_file_conf "${MARIADB_CONFIG_EXTRA}/file.cnf";
}

function write_user_conf ()
{
    logmsg "Setting root password in user cnf";

    set_file_conf "${MARIADB_USER_CNF}";
    chmod 0640 ${MARIADB_USER_CNF};
}

function set_file_conf ()
{
    local F="${1:-}"
    [[ -f "${F}.default" ]] && envsubst < "${F}.default" > "${F}";
}

function clean_prev ()
{
    logmsg "Cleaning up stale config and locks";

    [[ -f "${MARIADB_DATA}/sst_in_progress" ]] && rm -f "${MARIADB_DATA}/sst_in_progress";
    clean_locks;
    clean_user_conf;    
}

function clean_locks ()
{
    [[ -f "${MARIADB_SOCK}.lock" ]] && rm -f "${MARIADB_SOCK}.lock";
}

function clean_user_conf ()
{
    [[ -f "${MARIADB_USER_CNF}" ]] && rm -f "${MARIADB_USER_CNF}";
}

function add_peers ()
{
    logmsg "Looking for peers ...";

    local N=$GALERA_CLUSTER_PEERS
    export GALERA_CLUSTER_UP=0

    until [ $N -lt 0 ]; do
        if [ $N -ne $GALERA_NODE_ID ]; then
            logmsg "Trying ${GALERA_HOSTPREFIX}-${N}.${GALERA_CLUSTER_NAME}";
            if [ $(getent hosts ${GALERA_HOSTPREFIX}-${N}.${GALERA_CLUSTER_NAME} | wc -l) -eq 1 ]; then
                if $(nc -w 2 -z ${GALERA_HOSTPREFIX}-${N}.${GALERA_CLUSTER_NAME} 3306 > /dev/null 2>&1) ; then
                    echo -n " [UP]"
                    GALERA_CLUSTER_UP=1
                else
                    echo -n " [DOWN]"
                fi
            else
                echo -n " [NOT KNOWN]"
            fi
            echo ""
        fi

        N=$((N-1))
    done
}

function bootstrap_master_node ()
{
	logmsg "This is the first node in a stateful set and it has no grant tables and no other nodes are up - initialize";

	bak_save_file "${MARIADB_CONFIG_EXTRA}/wsrep.cnf";

	db_initialize;
	setup_users;

	logmsg "Finishing database initialization";
	killall mysqld && until [ $(pgrep -c mysqld) -eq 0 ]; do sleep 1; done

	logmsg "Master node db bootstrap done. MySQL shutdown";
	
	bak_restore_file "${MARIADB_CONFIG_EXTRA}/wsrep.cnf";
}

function bootstrap_child_node ()
{
	logmsg "This is not the first node in a stateful set and has no grant tables and at least one node is up - SST"

	db_delete_data 1;

	write_user_conf;
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
	[[ "${1:-0}" -eq 1 ]] && rm -Rf "${MARIADB_DATA}/*";
}

function db_initialize ()
{
	logmsg "Initializing database";

	db_delete_data 1;

	mysqld --initialize-insecure \
		--datadir=${MARIADB_DATA} \
		--user=${MARIADB_USER};
		
	db_initialize_check;
	write_user_conf;
}

function db_initialize_check ()
{
	mysqld --defaults-file=${MARIADB_CNF} \
		--datadir=${MARIADB_DATA} \
		--log-error=${MARIADB_LOG}/mysqld.log \
		--user=${MARIADB_USER} \
		--skip-networking &

	for I in {1..30}; do
		$(mysql -u root -S ${MARIADB_SOCK} -Nse "SELECT 1;" > /dev/null 2>&1) && break || sleep 2;
	done

	[[ ${I} -eq 30 ]] && logerror "Failed to initialize database";

	$(/usr/bin/mysqladmin -S ${MARIADB_SOCK} -u root password "${MARIADB_ROOT_PASSWORD}" 2>/dev/null) || logerror "Failed to initialize root password";
}

function init_config ()
{
    mk_newconf;
    add_peers;
logmsg "NEW INIT CONFIG APPROACH 2"
	local S=${CUR_STATUS:-0}
	
    if [[ $(is_master_node) = 1 && ! $(is_data_populated) = 1 && ! $(is_cluster_up) = 1 ]]; then
        S=0
logmsg "STATUS 0 = ${S}";
		bootstrap_master_node;

        [[ ${STARTFROMBACKUP} = "true" && -d ${GALERA_BACKUP} ]] && S=1
    elif [[ $(is_cluster_up) = 1 && ! $(is_data_populated) = 1 ]]; then
        S=2
logmsg "STATUS 2 = ${S}"
		bootstrap_child_node;

    elif [[ $(is_data_populated) = 1 ]]; then
        S=3
logmsg "STATUS 3 = ${S}"
		logmsg "Grant tables are present just attempt a start"
		write_user_conf
	else
		if [[ ${S} = -1 ]]; then
			logerror "ENV variables not set correctly or cluster down and this is not node-0" 1;
			logerror "need at least:" 1;
			logerror " · MARIADB_ROOT_PASSWORD=<password of root user>" 1;
			logerror " · SSTUSER_PASSWORD=<password for SST user>" 1;
			logerror " · CLUSTER_NAME=<name of cluster>";
		else
			logerror "Unknown CUR_STATUS. Aborting";
		fi
    fi

	export CUR_STATUS=${S:--1}
logmsg "STATUS INIT = ${CUR_STATUS}"
}

function init_node ()
{
logmsg "INIT MODE STATUS = ${1:-} - ${CUR_STATUS}"

    if [[ ! $(is_cluster_up) = 1 && $(is_master_node) = 1 ]]; then
        [[ -f ${GALERA_GRASTATE} ]] && sed -i "s/^safe_to_bootstrap.*$/safe_to_bootstrap: 1/g" ${GALERA_GRASTATE}
        BOOTARGS="--wsrep-new-cluster"
    fi

    trap 'kill ${!}; term_handler' SIGKILL SIGTERM SIGHUP SIGINT EXIT
    
    echo "BOOTARGS=${BOOTARGS}" > ${MARIADB_TMP}/bootargs;
}

#function run_service ()
#{
#    logmsg "Starting MySQL"
#    eval "mysqld --defaults-file=$MARIADB_CNF --datadir=$MARIADB_DATA --user=$MARIADB_USER $BOOTARGS 2>&1 &"
#
#    CUR_PID="$!"
#}

function set_sysusers_password ()
{
    [[ -z "$MARIADB_ROOT_PASSWORD" ]] && export MARIADB_ROOT_PASSWORD="$(get_rnd_password)";
    [[ -z "$GALERA_MARIABACKUP_PASSWORD" ]] && export GALERA_MARIABACKUP_PASSWORD="$(get_rnd_password)";
    [[ -z "$GALERA_REPLICATION_PASSWORD" ]] && export GALERA_REPLICATION_PASSWORD="$(get_rnd_password)";
    [[ -z "$GALERA_MONITOR_PASSWORD" ]] && export GALERA_MONITOR_PASSWORD="$(get_rnd_password)";
    [[ -z "$GALERA_CLUSTERCHECK_PASSWORD" ]] && export GALERA_CLUSTERCHECK_PASSWORD="$(get_rnd_password)";
}

function get_rnd_password ()
{
    echo "$(openssl rand -base64 16)";
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

function term_handler ()
{
    if [ $CUR_PID -ne 0 ]; then
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


function setup_users ()
{
    set_sysusers_password;

    logmsg "Setting up system users and securing defaults ...";

    $((mysql -Ns) << EOF
SET @@SESSION.SQL_LOG_BIN=0;

GRANT ALL PRIVILEGES \
  ON *.* TO 'root'@'%' IDENTIFIED BY '$MARIADB_ROOT_PASSWORD' WITH GRANT OPTION;

GRANT RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT \
  ON *.* TO 'xtrabackup'@'localhost' IDENTIFIED BY '$GALERA_REPLICATION_PASSWORD';

GRANT SELECT, CREATE USER, REPLICATION CLIENT, SHOW DATABASES, SUPER, PROCESS, REPLICATION SLAVE \
  ON *.* TO 'monitor'@'localhost' IDENTIFIED BY '${GALERA_MONITOR_PASSWORD}';

GRANT SELECT, CREATE USER, REPLICATION CLIENT, SHOW DATABASES, SUPER, PROCESS, REPLICATION SLAVE \
  ON *.* TO 'monitor'@'127.0.0.1' IDENTIFIED BY '${GALERA_MONITOR_PASSWORD}';

GRANT USAGE \
  ON *.* TO 'clustercheck'@'localhost' IDENTIFIED BY '$GALERA_CLUSTERCHECK_PASSWORD';

DELETE FROM mysql.user WHERE User='';

DROP DATABASE test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';

FLUSH PRIVILEGES;
EOF
) > /dev/null 2>&1
}
