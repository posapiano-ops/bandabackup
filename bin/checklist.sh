# 1. Creazione struttura directory
mkdir -p /backup/{postgresql/{daily,weekly,monthly,wal_archive,base},wildfly/{config,deployments,modules,data,logs,cli_export,snapshots},snapshots,reports}

# 2. Impostazione permessi
chown -R postgres:postgres /backup/postgresql
chown -R wildfly:wildfly /backup/wildfly
chmod 750 /backup/postgresql
chmod 750 /backup/wildfly

# 3. Copia script
cp postgres_backup.sh /usr/local/bin/
cp wildfly_backup.sh /usr/local/bin/
cp master_backup.sh /usr/local/bin/
cp restore_system.sh /usr/local/bin/
cp monitor_backups.sh /usr/local/bin/

# 4. Rendi eseguibili
chmod +x /usr/local/bin/*_backup.sh
chmod +x /usr/local/bin/restore_system.sh
chmod +x /usr/local/bin/monitor_backups.sh

# 5. Configura PostgreSQL per WAL archiving
# Modifica /var/lib/pgsql/data/postgresql.conf
vim /var/lib/pgsql/data/postgresql.conf

# 6. Restart PostgreSQL
systemctl restart postgresql

# 7. Test manuale
/usr/local/bin/postgres_backup.sh
/usr/local/bin/wildfly_backup.sh

# 8. Configura cron
crontab -e
# (aggiungi i job visti sopra)

# 9. Setup chiavi SSH per sync remoto
ssh-keygen -t rsa -b 4096 -f /root/.ssh/backup_key
ssh-copy-id -i /root/.ssh/backup_key.pub backup@remote-server

# 10. Test ripristino in ambiente di test
/usr/local/bin/restore_system.sh