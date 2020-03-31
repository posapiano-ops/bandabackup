# Rsnapshot root directory

snapshot root under which all backups are stored. Within this directory,
other directories are created for the various intervals that have been
defined. In the beginning it will be empty, but once rsnapshot has
been running for a week, it should look something like this:

```terminal
[root@localhost]# ls -l /home/bck/backups
drwxr-xr-x    7 root     root         4096 Dec 28 00:00 daily.0
drwxr-xr-x    7 root     root         4096 Dec 27 00:00 daily.1
drwxr-xr-x    7 root     root         4096 Dec 26 00:00 daily.2
drwxr-xr-x    7 root     root         4096 Dec 25 00:00 daily.3
drwxr-xr-x    7 root     root         4096 Dec 24 00:00 daily.4
drwxr-xr-x    7 root     root         4096 Dec 23 00:00 daily.5
drwxr-xr-x    7 root     root         4096 Dec 22 00:00 daily.6
drwxr-xr-x    7 root     root         4096 Dec 29 00:00 hourly.0
drwxr-xr-x    7 root     root         4096 Dec 28 20:00 hourly.1
drwxr-xr-x    7 root     root         4096 Dec 28 16:00 hourly.2
drwxr-xr-x    7 root     root         4096 Dec 28 12:00 hourly.3
drwxr-xr-x    7 root     root         4096 Dec 28 08:00 hourly.4
drwxr-xr-x    7 root     root         4096 Dec 28 04:00 hourly.5
```

Inside each of these directories is a "full" backup of that point in
time. The destination directory paths you specified under the backup
and backup_script parameters get stuck directly under these 
directories. example:

```bash
backup          /etc/           localhost/
```

The /etc/ directory will initially get backed up into
/home/bck/backups/hourly.0/localhost/etc/