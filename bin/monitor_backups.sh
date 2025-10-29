#!/bin/bash
# Script di monitoraggio backup
# Salvare come: /usr/local/bin/monitor_backups.sh

BACKUP_ROOT="/backup"
MAX_BACKUP_AGE=26  # ore
ALERT_EMAIL="admin@example.com"

check_backup_freshness() {
    local backup_type=$1
    local backup_file=$2
    
    if [ ! -f "$backup_file" ]; then
        echo "ALERT: Nessun backup $backup_type trovato!"
        return 1
    fi
    
    local age_hours=$(( ($(date +%s) - $(stat -c %Y "$backup_file")) / 3600 ))
    
    if [ $age_hours -gt $MAX_BACKUP_AGE ]; then
        echo "ALERT: Backup $backup_type troppo vecchio: $age_hours ore"
        return 1
    fi
    
    echo "OK: Backup $backup_type recente: $age_hours ore"
    return 0
}

# Verifica PostgreSQL
PG_BACKUP=$(find $BACKUP_ROOT/postgresql/daily -name "*.dump" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
check_backup_freshness "PostgreSQL" "$PG_BACKUP"

# Verifica WildFly
WF_BACKUP=$(find $BACKUP_ROOT/wildfly/config -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
check_backup_freshness "WildFly" "$WF_BACKUP"

# Verifica spazio disco
DISK_USAGE=$(df -h $BACKUP_ROOT | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 85 ]; then
    echo "ALERT: Spazio disco backup al ${DISK_USAGE}%"
fi