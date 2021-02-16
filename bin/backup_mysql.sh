#!/bin/sh
#
# Script bash for Backup Databases Mysql --- Compress in GZIP ---
# Author: PoSAPiaNO 10/04/2012 --- posapiano@gmail.com
#

### MySQL Server Login Info ###
MUSER="root"
MPASS="aeche7iX"
MHOST="localhost"
PORT=3307
#RETENTION=1

### Script Variables ###
MYSQL="$(which mysql)"
MYSQLDUMP="$(which mysqldump)"
FBKP="/root/rdb"
GZIP="$(which gzip)"
NOW="$(date +%d-%m-%Y)"

### Delete OLD DUMP ###
#find $FBKP -type f -name \*gz -mtime +$RETENTION -exec rm -f {} \;

### Start Databases Backup ###
DBS="$($MYSQL -u $MUSER -h $MHOST --port=$PORT --password=$MPASS -Bse 'show databases')"

for db in $DBS
do
        if [ $db != "information_schema" ] || [ $db != "performance_schema" ] ; then
                #FILE=$FBKP/$db"_"$NOW-$(date +"%H_%M_%S").sql.gz
                FILE=$FBKP/$db.sql.gz
                $MYSQLDUMP -u $MUSER -h $MHOST --port=$PORT --password=$MPASS $db --routines | $GZIP -9 > $FILE
        else
                #FILE=$FBKP/$db"_"$NOW-$(date +"%H_%M_%S").sql.gz
                FILE=$FBKP/$db.sql.gz
                $MYSQLDUMP -u $MUSER -h $MHOST --port=$PORT --password=$MPASS $db --routines --skip-lock-tables | $GZIP -9 > $FILE
        fi
done
