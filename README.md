# bandabackup
Backup with rsnapshot.
Setup and use rsnapshot to create incremental hourly, daily, weekly and monthly local backups, as well as remote backups.

System: CentOS 7.x

required: rsnapshot, rsync, openssl

1. Install rsnapshot and create user `bck`
```terminal
 $ sudo adduser bck
```
configure `conf/rsnapshot.conf` and check syntax
```bash
$ rsnapshot configtest
```
testing
```bash
$ rsnapshot -t daily
```
2. Setting up passwordless logins via SSH for rsync using SSH keys.
```bash
$ ssh-keygen -t rsa -b 4096 -C "My rsnapshot backup server key" 
```
Copy public key to remote:
```bash
$ ssh-copy-id -i ~/.ssh/id_rsa.pub root@example.cloud
```
or 
```bash
##############################
## WARNING OVERWRITING FILE ##
##############################
scp .ssh/id_rsa.pub root@example.com:.ssh/authorized_keys
```
3. Add this in `/etc/sudoers`
```terminal
## Backup
 Cmnd_Alias BACKUP = /usr/bin/rsnapshot, /usr/bin/vi /var/log/rsnapshot/rsnapshot.log, /usr/bin/rsync, /bin/ls, /bin/tee

## Allow bck to run Backup commands without password
bck    ALL=(root)       NOPASSWD: BACKUP
```
4. Configura crontab whit `conf/crontab`
```bash
$ crontab -e
```
