#!/usr/bin/env bash

if [ $(pgrep mysqld) ] || [ -f "/tmp/live.lock" ]; then

 if [ -f /opt/mysql/data/sst_in_progress ]; then
 # sst in progress marker - check how long this state has been
  if [ ! -f /tmp/sst.time ]; then
    echo -n $(date +%s) > /tmp/sst.time
  else
  # if more than 2 mins then check for evidence
    if [ $(date +%s) -gt $(( $(cat /tmp/sst.time) + 120 )) ]; then
      # if socat or xtrabackup (prepare) is running exit 0
      if $(pgrep socat >/dev/null 2>&1) || $(pgrep xtrabackup >/dev/null 2>&1); then
        exit 0
      else
        # sst has failed - mysql entered uninterutable state - kill it
        echo "SST failed"
        killall -9 mysqld
        exit 1
      fi	
    fi
  fi
fi
exit 0
else
exit 1
fi
