#!/bin/bash
# Incremental based on full backup at midnight Sunday and hourly (or 2,4,6,8 or 12 hourly) incremental backups until the following Sunday
# This script creates a rolling backup as applying hourly backups for 7 days would be onerous 
# This means it uses twice as much space but it leaves all your backups intact incase you want to go back to a specific hour
if [ -z "${BCKRETENTION}" ]; then
	BCKRETENTION="2" # this is weeks
fi
# Required as process needs a tmp dir
cd ~

if [ -z "$THROTTLE" ]; then
	# reduce IO by throttling xtrabackup (default is 10Mb/s)
	THROTTLE=10
fi
if [ -z "$PARALLEL" ]; then
	PARALLEL=2
fi

START=$(date +%s)
PROCESSLOG="${BACKUPDIR}/${CLUSTER_NAME}/$(date +%U)/$(date +%Y%m%d)/weekly-inc-${START}.log"
XTRABCKLOG="${BACKUPDIR}/${CLUSTER_NAME}/$(date +%U)/$(date +%Y%m%d)/weekly-inc-${START}-xtrabackup.log"
THISWEEK=$(date +%U)
THISDAY=$(date +%Y%m%d)
THISHOUR=$(date +%H)

mkdir -p ${BACKUPDIR}/${CLUSTER_NAME}/${THISWEEK}/${THISDAY}

if [ -d ${BACKUPDIR}/${CLUSTER_NAME}/${THISWEEK}/${THISDAY}/${THISHOUR} ]; then
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Backup directory present - exiting" | tee -a ${PROCESSLOG}
	exit 0
fi
# Get some variables
if [ $(date +%u) -eq 7 ]; then
	FULLBACKUP="${BACKUPDIR}/${CLUSTER_NAME}/$(date +%U)/$(date +%Y%m%d)/00"
	ROLLBACKBK="${BACKUPDIR}/${CLUSTER_NAME}/$(date +%U)/ROLLINGBK"
	SUNDAYBASE="${BACKUPDIR}/${CLUSTER_NAME}/$(date +%U)/$(date +%Y%m%d)"
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Today is Sunday, full backup should exist at $FULLBACKUP" | tee -a ${PROCESSLOG}
else
	FULLBACKUP="${BACKUPDIR}/${CLUSTER_NAME}/$(date -d "last sunday" +%U)/$(date -d "last sunday" +%Y%m%d)/00"
	ROLLBACKBK="${BACKUPDIR}/${CLUSTER_NAME}/$(date -d "last sunday" +%U)/ROLLINGBK"
	SUNDAYBASE="${BACKUPDIR}/${CLUSTER_NAME}/$(date -d "last sunday" +%U)/$(date -d "last sunday" +%Y%m%d)"
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Today is not Sunday, full backup should exist at ${FULLBACKUP}" | tee -a ${PROCESSLOG}
fi

if [ ! -d ${FULLBACKUP} ] || [ ! -f ${FULLBACKUP}/xtrabackup_checkpoints ]; then
	rm -rf ${FULLBACKUP}
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Full backup does not exist (or has failed), doing one now" | tee -a ${PROCESSLOG}
	mkdir -p ${SUNDAYBASE}
	if ! $(xtrabackup --throttle=${THROTTLE} \
	--parallel=${PARALLEL} \
	--compress \
	--backup \
	--innodb_use_native_aio=0 \
	--target-dir=${FULLBACKUP} \
	--datadir=/opt/mysql/data/ >> ${XTRABCKLOG} 2>&1); then
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] Running xtrabackup - see ${XTRABCKLOG} for details, removing folder so it can re-run cleanly" | tee -a ${PROCESSLOG}
	rm -rf ${FULLBACKUP} 2>&1 | tee -a ${PROCESSLOG}
	exit 1
	fi
else
	DAY=$(date +%Y%m%d)
    LAST="$(find ${BACKUPDIR}/${CLUSTER_NAME}/${THISWEEK}/${DAY} -name xtrabackup_checkpoints 2>/dev/null | sort | sed 's/\/xtrabackup_checkpoints//g' | tail -n1)"
    while [[ -z "$LAST" ]]; do
	    DAYS=$((DAYS+1))
	    DAY=$(date -d "${DAYS} day ago" +%Y%m%d)
	    LAST="$(find ${BACKUPDIR}/${CLUSTER_NAME}/${THISWEEK}/${DAY} -name xtrabackup_checkpoints 2>/dev/null | sort | sed 's/\/xtrabackup_checkpoints//g' | tail -n1)"
	    if [ "${DAY}" = "$(date -d "last sunday" +%Y%m%d)" ]; then
		    echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] Cant find sutable backup to increment off - exiting" | tee -a ${PROCESSLOG}
		    exit 1
	    fi
	done
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Doing incremental backup based on ${LAST}" | tee -a ${PROCESSLOG}
	if ! $(xtrabackup --throttle=${THROTTLE} \
	--parallel=${PARALLEL} \
	--compress \
	--backup \
	--innodb_use_native_aio=0 \
	--target-dir=${BACKUPDIR}/${CLUSTER_NAME}/${THISWEEK}/${THISDAY}/${THISHOUR} \
	--incremental-basedir=${LAST} \
	--datadir=/opt/mysql/data/ >> ${XTRABCKLOG} 2>&1); then
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] Running xtrabackup - see ${XTRABCKLOG} for details, removing folder so it can re-run cleanly" | tee -a ${PROCESSLOG}
	rm -rf ${BACKUPDIR}/${CLUSTER_NAME}/${THISWEEK}/${THISDAY}/${THISHOUR} 2>&1 | tee -a ${PROCESSLOG}
	exit 1
	fi
fi
END=$(date +%s)
echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Total run time $((END-START)) seconds" | tee -a ${PROCESSLOG}
# remove all backups and logs past ${BCKRETENTION} weeks
echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Checking for backups and logs past ${BCKRETENTION} weeks" | tee -a ${PROCESSLOG}
if [ -d ${BACKUPDIR}/${CLUSTER_NAME}/$(date -d "${BCKRETENTION} weeks ago" +%U) ]; then
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Removing ${BACKUPDIR}/${CLUSTER_NAME}/$(date -d "${BCKRETENTION} weeks ago" +%U)"
	rm -rf ${BACKUPDIR}/${CLUSTER_NAME}/$(date -d "${BCKRETENTION} weeks ago" +%U) 2>&1 | tee -a ${PROCESSLOG}
fi
exit 0