#!/bin/bash
# Verifica backup recente

BACKUP_DIR="/backup/mysql"
MAX_AGE_HOURS=25

LATEST=$(find $BACKUP_DIR -name "*.sql.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
AGE=$(( ($(date +%s) - $(stat -c %Y "$LATEST")) / 3600 ))

if [ $AGE -gt $MAX_AGE_HOURS ]; then
    echo "ALLARME: Backup troppo vecchio ($AGE ore)" | mail -s "Backup Alert" admin@example.com
    exit 1
fi

# Test ripristino
gunzip < "$LATEST" | mysql -u$DB_USER -p$DB_PASS test_restore_db
if [ $? -eq 0 ]; then
    echo "Verifica backup OK"
    mysql -u$DB_USER -p$DB_PASS -e "DROP DATABASE test_restore_db"
else
    echo "ERRORE: Backup corrotto!" | mail -s "Backup Corrupted" admin@example.com
fi