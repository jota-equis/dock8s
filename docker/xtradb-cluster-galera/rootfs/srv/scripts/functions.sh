#!/usr/bin/env bash

function logmsg ()
{
    echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] ${1:-}";
}

function logerror ()
{
    echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] ${1:-}";
    exit 1;
}

function write_user_conf ()
{
    logmsg "Setting root password in user cnf";

    [[ -f "${MARIADB_USER_CNF}.default" ]] && envsubst < "${MARIADB_USER_CNF}.default" > ${MARIADB_USER_CNF};
    chmod 0640 ${MARIADB_USER_CNF};
}

function mk_appdir ()
{
    mkdir -pm0750 $MARIADB_CONFIG_EXTRA $MARIADB_DATA $MARIADB_BIN $MARIADB_LOG \
    $MARIADB_LOGBIN $MARIADB_SQL $MARIADB_TMP $GALERA_BACKUP $GALERA_BOOTSTRAP;
    
    ln -s /run/mysqld $MARIADB_RUN;

    chown -R mysql:mysql $MARIADB_ROOT;
    
    clean_prev;
}

function clean_prev ()
{
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

    until [ $N -lt 0 ]; do
        if [ $N -ne $GALERA_NODEID ]; then
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

function set_file_conf ()
{
    local F="${1:-}"
    [[ -f "${F}.default" ]] && envsubst < "${F}.default" > "${F}";
}

function term_handler()
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
