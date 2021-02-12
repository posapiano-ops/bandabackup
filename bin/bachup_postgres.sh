#!/bin/bash
# Location to place backups.
# set -x # set echo on

BASEDIR='/home/postgres/rdb'
RETENTION=2

DATE="$(which date)"
FIND="$(which find)"
TAR="$(which tar)"
RM="$(which rm)"
MKDIR="$(which mkdir)"
PSQL="$(which psql)"
PGDUMP="$(which pg_dump)"
CUT="$(which cut)"
SED="$(which sed)"

# Location to place backups.
BACKUPDIR=$BASEDIR/backup_$($DATE +%Y-%m-%d)
$MKDIR -p $BACKUPDIR
TARFILE=$BACKUPDIR.tar.gz

databases=$($PSQL -l -t | $CUT -d'|' -f1 | $SED -e 's/ //g' -e '/^$/d')
for i in $databases; do
  if [ "$i" != "template0" ] && [ "$i" != "template1" ]; then
    now=$($DATE '+%Y-%m-%d %H:%M:%S')
    echo $now - Dumping $i to $BACKUPDIR/$i\_$($DATE +%Y-%m-%d)
    $PGDUMP -Fc $i > $BACKUPDIR/$i\_$($DATE +%Y-%m-%d).dmp
    $PGDUMP $i > $BACKUPDIR/$i\_$($DATE +%Y-%m-%d).sql
  fi
done

now=$($DATE '+%Y-%m-%d %H:%M:%S')
echo $now - Generating $TARFILE
#$TAR zcf $TARFILE $BACKUPDIR >/dev/null 2>&1
$TAR zcf $TARFILE -C/ ${BACKUPDIR#?}

now=$($DATE '+%Y-%m-%d %H:%M:%S')
echo $now - Deleting $BACKUPDIR
$RM -rf $BACKUPDIR

now=$($DATE '+%Y-%m-%d %H:%M:%S')
echo $now - Deleting old files
$FIND $BASEDIR -type f -name \*gz -mtime +$RETENTION -exec $RM {} \;
