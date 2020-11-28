#!/bin/bash
# Differential based on full backup at midnight Sunday and hourly (or 2,4,6,8 or 12 hourly) differential backups until the following Sunday
# This will create ever growing backups but you only have to apply the last to the first to restore
# To prepare to a certain day/hour e.g. Wednesday 13:00:
#  Prepare just that hour:
#   xtrabackup --prepare --apply-log-only --target-dir=/var/backup/<cluster>/<last sunday>/00 --incremental-dir=/var/backup/<cluster>/<wednesday>/13
# Then restore /var/backup/<cluster>/<last sunday>/00 as normal, on start crash recovery will take care of rollback phase
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
PROCESSLOG="${BACKUPDIR}/${CLUSTER_NAME}/$(date +%U)/$(date +%Y%m%d)/weekly-diff-${START}.log"
XTRABCKLOG="${BACKUPDIR}/${CLUSTER_NAME}/$(date +%U)/$(date +%Y%m%d)/weekly-diff-${START}-xtrabackup.log"
THISWEEK=$(date +%U)
THISDAY=$(date +%Y%m%d)
THISHOUR=$(date +%H)

mkdir -p ${BACKUPDIR}/${CLUSTER_NAME}/${THISWEEK}/${THISDAY}

# check if backup has been done for this hour
if [ -d ${BACKUPDIR}/${CLUSTER_NAME}/${THISWEEK}/${THISDAY}/${THISHOUR} ]; then
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Backup directory present - exiting" | tee -a ${PROCESSLOG}
	exit 0
fi
# Get some variables - if today is Sunday stuff is different
if [ $(date +%u) -eq 7 ]; then
	FULLBACKUP="${BACKUPDIR}/${CLUSTER_NAME}/$(date +%U)/$(date +%Y%m%d)/00"
	SUNDAYBASE="${BACKUPDIR}/${CLUSTER_NAME}/$(date +%U)/$(date +%Y%m%d)"
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Today is Sunday, full backup should exist at ${FULLBACKUP}" | tee -a ${PROCESSLOG}
else
	FULLBACKUP="${BACKUPDIR}/${CLUSTER_NAME}/$(date -d "last sunday" +%U)/$(date -d "last sunday" +%Y%m%d)/00"
	SUNDAYBASE="${BACKUPDIR}/${CLUSTER_NAME}/$(date -d "last sunday" +%U)/$(date -d "last sunday" +%Y%m%d)"
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Today is not Sunday, full backup should exist at ${FULLBACKUP}" | tee -a ${PROCESSLOG}
fi

# do a full backup if one does not exist
if [ ! -d ${FULLBACKUP} ] || [ ! -f ${FULLBACKUP}/xtrabackup_checkpoints ]; then
	rm -rf ${FULLBACKUP}
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Full backup does not exist (or has failed), doing one now" | tee -a ${PROCESSLOG}
	mkdir -p ${SUNDAYBASE}
	if ! $(xtrabackup --throttle=${THROTTLE} \
    --compress \
	--parallel=${PARALLEL} \
	--backup \
	--innodb_use_native_aio=0 \
	--target-dir=${FULLBACKUP} \
	--datadir=/opt/mysql/data/ >> ${XTRABCKLOG} 2>&1); then
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] Running xtrabackup - see ${XTRABCKLOG} for details, removing folder so it can re-run cleanly" | tee -a ${PROCESSLOG}
	  rm -rf ${FULLBACKUP} 2>&1 | tee -a ${PROCESSLOG}
	  exit 1
	fi
else
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Doing differential backup based on ${FULLBACKUP}" | tee -a ${PROCESSLOG}
	if ! $(xtrabackup --throttle=${THROTTLE} \
    --compress \
	--parallel=${PARALLEL} \
	--backup \
	--innodb_use_native_aio=0 \
	--target-dir=${BACKUPDIR}/${CLUSTER_NAME}/${THISWEEK}/${THISDAY}/${THISHOUR} \
	--incremental-basedir=${FULLBACKUP} \
	--datadir=/opt/mysql/data/ >> ${XTRABCKLOG} 2>&1); then
	   echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] With differential backup - see ${XTRABCKLOG} for details, removing folder so it can re-run cleanly" | tee -a ${PROCESSLOG}
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