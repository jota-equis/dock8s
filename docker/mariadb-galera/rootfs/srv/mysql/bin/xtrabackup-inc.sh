#!/bin/bash
# Incremental based on full backup at midnight (24 backups per day 1 big 23 approx same size)
#
# To prepare to a certain hour e.g. 13:00:
#  Prepare each hour in turn:
#   xtrabackup --prepare --apply-log-only --target-dir=/var/backup/<cluster>/YYYYMMDD/00 --incremental-dir=/var/backup/<cluster>/YYYYMMDD/01
#   xtrabackup --prepare --apply-log-only --target-dir=/var/backup/<cluster>/YYYYMMDD/00 --incremental-dir=/var/backup/<cluster>/YYYYMMDD/02
#   ....
#   xtrabackup --prepare --apply-log-only --target-dir=/var/backup/<cluster>/YYYYMMDD/00 --incremental-dir=/var/backup/<cluster>/YYYYMMDD/13
# Then restore /var/backup/<cluster>/YYYYMMDD/00 as normal, on start crash recovery will take care of rollback phase
if [ -z "${BCKRETENTION}" ]; then
	BCKRETENTION="5"
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

THISDAY=$(date +%Y%m%d)
THISHOUR=$(date +%H)
START=$(date +%s)
PROCESSLOG="${BACKUPDIR}/${CLUSTER_NAME}/${THISDAY}/daily-inc-${START}.log"
XTRABCKLOG="${BACKUPDIR}/${CLUSTER_NAME}/${THISDAY}/daily-inc-${START}-xtrabackup.log"

mkdir -p ${BACKUPDIR}/${CLUSTER_NAME}/${THISDAY}
echo "$(date "+%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Starting hourly per day incremental backup" | tee -a ${PROCESSLOG}

if [ $(date +%H) -eq 0 ] || [ ! -d "${BACKUPDIR}/${CLUSTER_NAME}/${THISDAY}/00" ]; then
	echo "$(date "+%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Starting full backup, does not exist or it is hour 0" | tee -a ${PROCESSLOG}
	if ! $(xtrabackup --throttle=${THROTTLE} \
	--parallel=${PARALLEL} \
	--compress \
	--backup \
	--target-dir=${BACKUPDIR}/${CLUSTER_NAME}/${THISDAY}/00 \
	--datadir=/opt/mysql/data/ >> ${XTRABCKLOG} 2>&1); then
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] Running xtrabackup - see ${XTRABCKLOG} for details, removing folder so it can re-run cleanly" | tee -a ${PROCESSLOG}
	rm -rf ${BACKUPDIR}/${CLUSTER_NAME}/${THISDAY}/00 2>&1 | tee -a ${PROCESSLOG}
	exit 1
	fi
else
	LAST="$(find ${BACKUPDIR}/${CLUSTER_NAME}/${THISDAY} -name xtrabackup_checkpoints 2>/dev/null | sort | sed 's/\/xtrabackup_checkpoints//g' | tail -n1)"
    if [ -z "$LAST" ]; then
		echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] Cant find sutable backup to increment off - exiting" | tee -a ${PROCESSLOG}
		exit 1
	fi
	echo "$(date "+%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Starting incremental backup based on ${LAST}" | tee -a ${PROCESSLOG}
	if ! $(xtrabackup --throttle=${THROTTLE} \
	--parallel=${PARALLEL} \
	--compress \
	--backup \
	--target-dir=${BACKUPDIR}/${CLUSTER_NAME}/${THISDAY}/${THISHOUR} \
	--incremental-basedir=${LAST} \
	--datadir=/opt/mysql/data/ >> ${XTRABCKLOG} 2>&1); then
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] Running xtrabackup - see ${XTRABCKLOG} for details, removing folder so it can re-run cleanly" | tee -a ${PROCESSLOG}
	rm -rf ${BACKUPDIR}/${CLUSTER_NAME}/${THISDAY}/${THISHOUR} 2>&1 | tee -a ${PROCESSLOG}
	exit 1
	fi
fi
END=$(date +%s)
echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Total run time $((END-START)) seconds" | tee -a ${PROCESSLOG}
# remove all backups and logs past ${BCKRETENTION} days
echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Checking for backups and logs past ${BCKRETENTION} days" | tee -a ${PROCESSLOG}
REMBEFORE=$(date -d "${BCKRETENTION} days ago" +%s)
for d in $(find ${BACKUPDIR}/${CLUSTER_NAME} -maxdepth 1 -mindepth 1 -type d); do
DIR=$(basename $d)
if [[ "${DIR}" =~ ^[0-9]+$ ]]; then
if [ $(date -d $DIR +%s) -lt ${REMBEFORE} ]; then
echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Removing ${DIR}"
rm -rf ${BACKUPDIR}/${CLUSTER_NAME}/${DIR} 2>&1 | tee -a ${PROCESSLOG}
fi
fi
done
exit 0
