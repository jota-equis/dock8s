#!/bin/bash

if [ -z "${BCKRETENTION}" ]; then
  BCKRETENTION="5"
fi

SLOWLOG="$(mysql -Nse "SELECT VARIABLE_VALUE FROM performance_schema.global_variables WHERE VARIABLE_NAME='slow_query_log_file';" 2>/dev/null)"
GENLOG="$(mysql -Nse "SELECT VARIABLE_VALUE FROM performance_schema.global_variables WHERE VARIABLE_NAME='general_log_file';" 2>/dev/null)"
if [ ! -z "${SLOWLOG}" ] && [ ! -z "${GENLOG}" ]; then
  FILES=( ${SLOWLOG} ${GENLOG} )
  COMM=( "FLUSH SLOW LOGS;" "FLUSH GENERAL LOGS;" )
  a=0
  for FILE in "${FILES[@]}"; do
    if [ -f $FILE ]; then
      if [ $(stat --format=%s $FILE) -gt 104857600 ]; then
        for i in {3..1}; do
          if [ -f ${FILE}.${i} ]; then
            mv -f ${FILE}.${i} ${FILE}.$((i+1))
          fi
        done
        if [ -f ${FILE}.6 ]; then
          rm -f ${FILE}.6
        fi
        mv ${FILE} ${FILE}.1
        touch ${FILE}
        chmod 0650 ${FILE}
        mysql -Nse "${COMM[$a]}" > /dev/null 2>&1
        echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] $FILE rotated"
      else
        echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] $FILE not rotated - not big enough"
      fi
    else
      # file does not exist
      echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] $FILE does not exist"
    fi
  a=$((a+1))
  done
  if [ -n "${BACKUPDIR}" ]; then
    echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Backing up BINARY logs"
    NODEID=$(echo $(hostname) | rev | cut -d- -f1 | rev)
    mkdir -p /mnt/backup/binlogs/xtradb/${NODEID}
    if ! $(rsync -rt --size-only /opt/mysql/binlogs/ /mnt/backup/binlogs/xtradb/${NODEID}/  2>/dev/null); then
      echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 2 [Warning] Rsync did not exit 0"
    fi

    if ! $(find /mnt/backup/binlogs/xtradb/${NODEID} -mtime +${BCKRETENTION} -exec rm -f {} \; 2>/dev/null); then
      echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 2 [Warning] Binlog retention did not exit 0"
    fi
  fi
else
  echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 2 [Warning] MySQL not up - cant retrieve log paths"
fi

