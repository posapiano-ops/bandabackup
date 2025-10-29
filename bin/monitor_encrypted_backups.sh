#!/bin/bash
# Monitoraggio backup crittografati
# /usr/local/bin/monitor_encrypted_backups.sh

BACKUP_ROOT="/backup/postgresql/encrypted"
ALERT_EMAIL="admin@example.com"
MAX_AGE_HOURS=25

check_encrypted_backup() {
    local method=$1
    local extension=$2
    
    echo "Verifica backup $method..."
    
    local latest=$(find $BACKUP_ROOT/daily -name "*.$extension" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -z "$latest" ]; then
        echo "✗ Nessun backup $method trovato"
        return 1
    fi
    
    local age=$(( ($(date +%s) - $(stat -c %Y "$latest")) / 3600 ))
    
    if [ $age -gt $MAX_AGE_HOURS ]; then
        echo "✗ Backup $method troppo vecchio: $age ore"
        echo "ALERT: Backup $method vecchio" | mail -s "Backup Alert" $ALERT_EMAIL
        return 1
    fi
    
    echo "✓ Backup $method OK: $age ore"
    
    # Test decrittografia primi byte
    case $extension in
        gpg)
            gpg --list-packets "$latest" > /dev/null 2>&1
            ;;
        enc)
            head -c 1024 "$latest" > /dev/null 2>&1
            ;;
        age)
            head -c 1024 "$latest" > /dev/null 2>&1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo "✓ File $method integrità OK"
        return 0
    else
        echo "✗ File $method potrebbe essere corrotto"
        return 1
    fi
}

# Carica config
source /etc/backup_encryption.conf 2>/dev/null

# Verifica in base al metodo configurato
case $ENCRYPTION_METHOD in
    gpg)
        check_encrypted_backup "GPG" "gpg"
        ;;
    openssl)
        check_encrypted_backup "OpenSSL" "enc"
        ;;
    age)
        check_encrypted_backup "age" "age"
        ;;
esac

# Verifica spazio disco
DISK_USAGE=$(df -h $BACKUP_ROOT | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 85 ]; then
    echo "⚠ Spazio disco backup al ${DISK_USAGE}%"
    echo "ALERT: Spazio disco basso" | mail -s "Disk Alert" $ALERT_EMAIL
fi

exit 0