#!/bin/bash
# Backup files PHP

APP_DIR="/var/www/html"
BACKUP_DIR="/backups/files"
DATE=$(date +%Y%m%d_%H%M%S)
EXCLUDE_FILE="/etc/backup_exclude.txt"

# Crea directory se non esiste
mkdir -p $BACKUP_DIR

# Escludi vendor, cache, temp
tar -czf $BACKUP_DIR/app_${DATE}.tar.gz \
    --exclude='vendor' \
    --exclude='node_modules' \
    --exclude='*.log' \
    --exclude='cache/*' \
    -C $APP_DIR .

# Mantieni ultimi 14 backup
find $BACKUP_DIR -name "app_*.tar.gz" -mtime +14 -delete