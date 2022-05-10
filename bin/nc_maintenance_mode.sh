#!/bin/bash
# Based on RdH7
# Run as "./nc_maintenance_mode.sh on" or "./nc_maintenance_mode.sh off" 

if [ $1 = 'on'] then
    sudo -u apache php /var/www/html/nextcloud/occ maintenance:mode --on
else
    sudo -u apache php /var/www/html/nextcloud/occ maintenance:mode --off 
fi
