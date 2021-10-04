#!/bin/sh
#
# Script bash for Backup Subversion --- Compress in GZIP ---
# Author: PoSAPiaNO 20170927 --- posapiano@gmail.com
#

RETENTION=30

### Script Variables ###
SVNADMIN="$(which svnadmin)"
SVNDUMP="dump"
FBKP="/root/bck"
PATHREPOS="/var/www/svn/"
GZIP="$(which gzip)"
NOW="$(date +%d-%m-%Y)"


### Start SVN Backup ###
for repo in $PATHREPOS*
do
	FILE=$FBKP${repo##*/}"_"$NOW-$(date +"%H_%M_%S").dump.gz
    test -d $repo && $SVNADMIN dump $repo | $GZIP -9 > $FILE
	#echo $FILE
done


# Remove old days
find $FBKP -type f -name \*gz -mtime +$RETENTION -exec rm -f {} \;


