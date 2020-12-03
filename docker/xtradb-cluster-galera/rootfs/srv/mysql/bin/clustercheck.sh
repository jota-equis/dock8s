#!/usr/bin/env bash
#

if [[ $1 == '-h' || $1 == '--help' ]];then
    echo "Usage: $0 <user> <pass> <available_when_donor=0|1> <log_file> <available_when_readonly=0|1> <defaults_extra_file>"
    exit
fi

if [ -f /tmp/drain.lock ]; then
echo "Node is draining"
exit 1
fi

if [ -f /opt/mysql/data/sst_in_progress ]; then
echo "SST in progress"
exit 1
fi

if [ -f /tmp/restore.lock ]; then
echo "Node is restoring from backup"
exit 1
fi

MYSQL_USERNAME="${1-monitor}" 
MYSQL_PASSWORD="${2-${MONITOR_PASSWORD}}" 
AVAILABLE_WHEN_DONOR=${3:-1}
ERR_FILE="${4:-/var/lib/mysql/clustercheck.log}" 
AVAILABLE_WHEN_READONLY=${5:-1}
DEFAULTS_EXTRA_FILE=${6:-/etc/my.cnf}

#Timeout exists for instances where mysqld may be hung
TIMEOUT=10

EXTRA_ARGS="--protocol=TCP --host=127.0.0.1"
if [[ -n "$MYSQL_USERNAME" ]]; then
    EXTRA_ARGS="$EXTRA_ARGS --user=${MYSQL_USERNAME}"
fi
if [[ -n "$MYSQL_PASSWORD" ]]; then
    EXTRA_ARGS="$EXTRA_ARGS --password=${MYSQL_PASSWORD}"
fi
if [[ -r $DEFAULTS_EXTRA_FILE ]];then 
    MYSQL_CMDLINE="mysql --defaults-extra-file=$DEFAULTS_EXTRA_FILE -nNE --connect-timeout=$TIMEOUT ${EXTRA_ARGS}"
else 
    MYSQL_CMDLINE="mysql -nNE --connect-timeout=$TIMEOUT ${EXTRA_ARGS}"
fi

ipaddr=$(hostname -i | awk ' { print $1 } ')
hostname=$(hostname)

if [ $(ps aux | grep -c [-]-wsrep-new-cluster) -eq 1 ]; then
STATE=$(mysql ${EXTRA_ARGS} -Nse "SHOW STATUS LIKE 'wsrep_%';" 2>${ERR_FILE} | egrep 'wsrep_local_state[[:space:]]|wsrep_cluster_status|wsrep_cluster_size' | sort | awk '{print $2}')
STATE=$(echo $STATE | sed "s/[[:space:]]/:/g")

if [ $(echo $STATE | cut -d: -f1) -ge 3 ] && [ $(echo $STATE | cut -d: -f2) = "Primary" ] && [ $(echo $STATE | cut -d: -f3) -eq 4 ]; then
echo "Un Bootstrapping"
killall mysqld
exit 1
fi

fi

if [ ! "$(mysql ${EXTRA_ARGS} -se "show status like 'wsrep_cluster_status'\G" 2>${ERR_FILE} | grep Value | awk '{print $2}')" = "Primary" ] && [ "$(mysql ${EXTRA_ARGS} -se "SHOW STATUS LIKE 'wsrep_cluster_size'\G" 2>${ERR_FILE} | grep Value | awk '{print $2}')" = "1" ]; then
# Cluster has lost quoram and is down to one node, try and recover
# Check that DNS and Kubernetes API are up otherwise protect data and dont bootstrap
if $(nc -w 1 -zu $(cat /etc/resolv.conf | grep nameserver | awk '{print $2}') 53) && $(nc -zw 1 ${KUBERNETES_SERVICE_HOST} ${KUBERNETES_SERVICE_PORT}); then
NODEID=$(echo $(hostname) | rev | cut -d- -f1 | rev)
HOSTPREFIX=$(echo $(hostname) | rev | cut -d- -f2- | rev)
CLUSTERUP=0
if [ -z "$CLUSTERSIZE" ]; then
N=2
else
N=$((CLUSTERSIZE-1))
fi
until [ $N -lt 0 ]; do
 if [ $N -ne $NODEID ]; then
  if $(host -W 2 ${HOSTPREFIX}-${N}.${SSSVC} > /dev/null 2>&1); then
   if $(nc -w 2 -z ${HOSTPREFIX}-${N}.${SSSVC} 3306 > /dev/null 2>&1) ; then
    CLUSTERUP=1
   fi
  fi
 fi
N=$((N-1))
done 
if [ $CLUSTERUP -eq 0 ]; then # boostrap to try and recover other starting pods
mysql --defaults-file=/opt/mysql/.my.cnf -Nse "SET GLOBAL wsrep_provider_options='pc.bootstrap=TRUE'"
fi
fi # Kube DNS is available amd so is the API (overlay networking is working)
fi # This mysqld process is up but cluster size = 1 and not PRIMARY

#
# Perform the query to check the wsrep_local_state
#
WSREP_STATUS=($($MYSQL_CMDLINE -e "SHOW GLOBAL STATUS LIKE 'wsrep_%';" 2>${ERR_FILE} | grep -A 1 -E 'wsrep_local_state$|wsrep_cluster_status$' | sed -n -e '2p'  -e '5p' | tr '\n' ' '))
 
if [[ ${WSREP_STATUS[1]} == 'Primary' && ( ${WSREP_STATUS[0]} -eq 4 || ( ${WSREP_STATUS[0]} -eq 2 && $AVAILABLE_WHEN_DONOR -eq 1 ) ) ]]
then 

    # Check only when set to 0 to avoid latency in response.
    if [[ $AVAILABLE_WHEN_READONLY -eq 0 ]];then
        READ_ONLY=$($MYSQL_CMDLINE -e "SHOW GLOBAL VARIABLES LIKE 'read_only';" \
                    2>${ERR_FILE} | tail -1 2>>${ERR_FILE})

        if [[ "${READ_ONLY}" == "ON" ]];then 
            # Percona XtraDB Cluster node local state is 'Synced', but it is in
            # read-only mode. The variable AVAILABLE_WHEN_READONLY is set to 0.
            # Shell return-code is 1
	    exit 1
        fi

    fi
    # if ProxySQL settings provided attempt to sync users (check if ProxySQL is up)
    if [ -n "$PROXYSRV" ]; then
        if $(nc -z $PROXYSRV $PROXYPRT); then
            declare -A mysql
            declare -A proxy
            CHG=0
            while read u p; do
            mysql[$u]=$p
            done < <(mysql -Nse "SELECT DISTINCT user,authentication_string FROM mysql.user WHERE host<>'localhost' AND user<>'root' ORDER BY user;")
            while read u p; do
            proxy[$u]=$p
            done < <(mysql --defaults-file=/opt/mysql/bin/.proxy.cnf -Nse "SELECT username,password FROM runtime_mysql_users ORDER BY username;")

            # Add users
            for user in ${!mysql[@]}; do
            if [ ! ${proxy[$user]+_} ] || [ ! "${proxy[$user]}" = "${mysql[$user]}" ]; then
            # Add user to ProxySQL
            mysql --defaults-file=/opt/mysql/bin/.proxy.cnf -Nse "REPLACE INTO mysql_users (username,password,active,default_hostgroup) VALUES ('$user','${mysql[$user]}',1,10);" 2>>${ERR_FILE} || echo "Failed to add user $u to ProxySQL"
            CHG=$((CHG+1))
            fi
            done
            # Remove users
            for user in ${!proxy[@]}; do
            if [ ! ${mysql[$user]+_} ]; then
            # Remove user
            mysql --defaults-file=/opt/mysql/bin/.proxy.cnf -Nse "DELETE FROM mysql_users WHERE username='$user';" 2>>${ERR_FILE} || echo "Failed to delete user $u from ProxySQL"
            CHG=$((CHG+1))
            fi
            done
            if [ $CHG -gt 0 ]; then
              mysql --defaults-file=/opt/mysql/bin/.proxy.cnf -Nse "LOAD MYSQL USERS TO RUNTIME;" 2>>${ERR_FILE} || echo "Failed to load users into runtime ProxySQL"
            fi
        fi
    fi
    # Percona XtraDB Cluster node local state is 'Synced'
    # Shell return-code is 0
    exit 0
else 
    # Percona XtraDB Cluster node local state is NOT 'Synced'
    # Shell return-code is 1
    exit 1
fi 
