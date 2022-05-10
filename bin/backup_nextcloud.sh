#! /bin/bash
# Bozza per local backup

user=root
backups=/mnt/0/backups

if [[ $EUID > 0 ]]
  then echo "Please run as root"
  exit
fi

# maintenance mode on
# nextcloud.occ maintenance:mode --on
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on

# if there is no backups directory then create it
if [ ! -d $backups ]
  then
  mkdir $backups
  chown $user:$user $backups
fi

bakdir=$backups/backup-$(date +%Y%m%d)

# config
echo "Backing up config file..."
rsync -Aax /snap/nextcloud/current/htdocs/config/config.php $bakdir/

# database
echo "Backing up database..."
nextcloud.mysqldump > $bakdir/sqlbkp.bak

# nextcloud-data
echo "Backing up data..."
rsync -Aax /var/snap/nextcloud/common/nextcloud/data/ $bakdir/nextcloud-data/

# owner manolis:manolis
chown -R $user:$user $bakdir

# maintenance mode off
#nextcloud.occ maintenance:mode --off
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off


echo "Backup finished."
echo "When restoring, don't forget to set the correct permissions."