#!/bin/bash
NOW=$(date +"%d-%m-%Y.%H-%M-%S")
LOGFILE="/home/bck/logs/log.$NOW.txt"
ssh appuserbck@remote.host 'sudo mount -t nfs appuserbck:remote_nas /mnt/Backup/'
sudo rsync -ah --log-file=$LOGFILE --rsync-path="sudo rsync" -e 'ssh -i /home/bck/.ssh/id_rsa' /home/bck/backup/daily.0/destination/folder appuserbck@remote.host:/mnt/Backup/snapshots/destinationfolder
ssh appuserbck@remote.host 'sudo umount /mnt/Backup/'
