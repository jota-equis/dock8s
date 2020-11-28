#!/bin/bash
# This creates a file directly compatible with STARTFROMBACKUP=true
if [ -z "${BCKRETENTION}" ]; then
	BCKRETENTION="5"
fi
# Required as process needs a tmp dir
cd ~

if [ -z "$THROTTLE" ]; then
# reduce IO by throttling xtrabackup (default is 10Mb/s)
THROTTLE=10
fi

START=$(date +%s)
PROCESSLOG="${BACKUPDIR}/backup-${CLUSTER_NAME}-${START}.log"
XTRABCKLOG="${BACKUPDIR}/backup-${CLUSTER_NAME}-${START}-xtrabackup.log"
echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Starting full backup" | tee -a ${PROCESSLOG}
if ! $(xtrabackup --backup --datadir=/opt/mysql/data --throttle=${THROTTLE} --stream=tar 2>${XTRABCKLOG} | gzip --fast - > ${BACKUPDIR}/backup-${CLUSTER_NAME}-${START}.tar.gz); then
	echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 1 [Error] Backup failed - removing debris, see ${XTRABCKLOG} for details" | tee -a ${PROCESSLOG}
	if [ -f ${BACKUPDIR}/backup-${CLUSTER_NAME}-${START}.tar.gz ]; then
		rm -f ${BACKUPDIR}/backup-${CLUSTER_NAME}-${START}.tar.gz
	fi
fi
END=$(date +%s)
echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Total run time $((END-START)) seconds" | tee -a ${PROCESSLOG}
# remove all backups and logs past 
echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Checking for backups and logs past ${BCKRETENTION} days" | tee -a ${PROCESSLOG}
for f in $(ls ${BACKUPDIR}); do 
EXRACTTS="$(echo $f | cut -d- -f3| cut -d. -f1)"
if [[ "${EXRACTTS}" =~ ^[0-9]+$ ]]; then
if [ $(date -d "${BCKRETENTION} days ago" +%s) -gt ${EXRACTTS} ]; then 
echo "$(date +"%Y-%m-%dT%H:%M:%S.%6NZ") 0 [Info] Removing $f" | tee -a ${PROCESSLOG}
rm -f ${BACKUPDIR}/$f 2>&1 | tee -a ${PROCESSLOG}
fi
fi
done
exit 0