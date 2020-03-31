#!/bin/bash
NOW=$(date +"%d-%m-%Y.%H-%M-%S")
LOGFILE="/home/bck/logs/log.$NOW.txt"
ssh appuserbck@remote.host 'sudo mount -t nfs nasremote:Backup /mnt/Backup2/'
sudo rsync -ah --log-file=$LOGFILE --rsync-path="sudo rsync" -e 'ssh -i /home/bck/.ssh/id_rsa' /home/bck/backup/daily.0/APPS1/FS appuserbck@192.168.1.174:/mnt/Backup2/snapshots/APPS1
ssh appuserbck@remote.host 'sudo umount /mnt/Backup2/'
