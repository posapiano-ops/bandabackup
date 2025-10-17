#!/bin/bash
# Salvare come /usr/local/bin/mysql_backup.sh

# Configurazione
DB_USER="your_user"
DB_PASS="your_password"
DB_PORT=3306
DB_HOST=localhost
#DB_NAME="your_database"
BACKUP_DIR="/backups/mysql"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

# Crea directory se non esiste
mkdir -p $BACKUP_DIR

# Selezione dei database presenti sul server
DBS="$(mysql -u $DB_USER -h $DB_HOST --port=$DB_PORT --password=$DB_PASS -Bse 'show databases')"

for DB_NAME in $DBS
do
    if [ $DB_NAME != "information_schema" ] || [ $DB_NAME != "performance_schema" ] ; then
        # Backup con compressione
        mysqldump -u$DB_USER -p$DB_PASS \
            -h $MHOST --port=$PORT \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            $DB_NAME | gzip -9 > $BACKUP_DIR/${DB_NAME}_${DATE}.sql.gz
    fi
done

# Rimuovi backup vecchi
find $BACKUP_DIR -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

# Verifica integrità
if [ $? -eq 0 ]; then
    echo "Backup completato: ${DB_NAME}_${DATE}.sql.gz"
else
    echo "ERRORE nel backup!" | mail -s "Backup Failed" admin@example.com
fi