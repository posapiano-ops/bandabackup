#!/bin/bash
# Script completo di backup PostgreSQL per produzione
# Salvare come: /usr/local/bin/postgres_backup.sh

#===========================================
# CONFIGURAZIONE
#===========================================
PGHOST="localhost"
PGPORT="5432"
PGUSER="postgres"
PGDATABASE="your_database"
BACKUP_DIR="/backup/postgresql"
LOG_DIR="/var/log/postgresql_backup"
DATE=$(date +%Y%m%d_%H%M%S)
DAY=$(date +%A)
RETENTION_DAILY=7
RETENTION_WEEKLY=30
RETENTION_MONTHLY=365

# Email per notifiche
ADMIN_EMAIL="admin@example.com"

# Crea directory necessarie
mkdir -p $BACKUP_DIR/{daily,weekly,monthly,wal_archive}
mkdir -p $LOG_DIR

#===========================================
# LOGGING
#===========================================
LOG_FILE="$LOG_DIR/backup_${DATE}.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "========================================="
echo "Backup PostgreSQL iniziato: $(date)"
echo "========================================="

#===========================================
# FUNZIONI
#===========================================

# Invia notifica email
send_notification() {
    local subject="$1"
    local message="$2"
    echo "$message" | mail -s "$subject" $ADMIN_EMAIL
}

# Verifica spazio disco
check_disk_space() {
    local required_space=10  # GB
    local available=$(df -BG $BACKUP_DIR | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ "$available" -lt "$required_space" ]; then
        echo "ERRORE: Spazio disco insufficiente. Disponibili: ${available}GB"
        send_notification "Backup Failed - Low Disk Space" "Spazio disponibile: ${available}GB"
        exit 1
    fi
    echo "Spazio disco OK: ${available}GB disponibili"
}

# Test connessione database
test_connection() {
    if ! pg_isready -h $PGHOST -p $PGPORT -U $PGUSER > /dev/null 2>&1; then
        echo "ERRORE: Impossibile connettersi a PostgreSQL"
        send_notification "Backup Failed - Connection Error" "PostgreSQL non raggiungibile"
        exit 1
    fi
    echo "Connessione a PostgreSQL: OK"
}

#===========================================
# BACKUP LOGICO (pg_dump)
#===========================================

backup_logical() {
    local backup_type=$1
    local backup_subdir=$2
    
    echo "Inizio backup logico ($backup_type)..."
    
    # Backup con formato custom (compresso e ottimizzato per pg_restore)
    local backup_file="$BACKUP_DIR/$backup_subdir/${PGDATABASE}_${backup_type}_${DATE}.dump"
    
    pg_dump -h $PGHOST -p $PGPORT -U $PGUSER \
        -F c \
        -b \
        -v \
        -f "$backup_file" \
        $PGDATABASE
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "$backup_file" | cut -f1)
        echo "Backup logico completato: $backup_file (${size})"
        
        # Verifica integrità
        if pg_restore -l "$backup_file" > /dev/null 2>&1; then
            echo "Verifica integrità backup: OK"
            echo "$backup_file" > "$BACKUP_DIR/last_successful_backup.txt"
            return 0
        else
            echo "ERRORE: Backup corrotto!"
            send_notification "Backup Failed - Corrupted File" "Il backup $backup_file è corrotto"
            return 1
        fi
    else
        echo "ERRORE: Backup fallito"
        send_notification "Backup Failed" "pg_dump fallito per $PGDATABASE"
        return 1
    fi
}

#===========================================
# BACKUP RUOLI E GLOBALS
#===========================================

backup_globals() {
    echo "Backup ruoli e configurazioni globali..."
    
    local globals_file="$BACKUP_DIR/daily/globals_${DATE}.sql"
    
    pg_dumpall -h $PGHOST -p $PGPORT -U $PGUSER \
        --globals-only \
        -f "$globals_file"
    
    if [ $? -eq 0 ]; then
        gzip "$globals_file"
        echo "Backup globals completato: ${globals_file}.gz"
    else
        echo "ERRORE: Backup globals fallito"
    fi
}

#===========================================
# BACKUP SCHEMA ONLY
#===========================================

backup_schema() {
    echo "Backup schema database..."
    
    local schema_file="$BACKUP_DIR/daily/schema_${DATE}.sql"
    
    pg_dump -h $PGHOST -p $PGPORT -U $PGUSER \
        -s \
        -f "$schema_file" \
        $PGDATABASE
    
    if [ $? -eq 0 ]; then
        gzip "$schema_file"
        echo "Backup schema completato: ${schema_file}.gz"
    else
        echo "ERRORE: Backup schema fallito"
    fi
}

#===========================================
# BACKUP INCREMENTALE (WAL)
#===========================================

setup_wal_archiving() {
    # Da configurare in postgresql.conf:
    # wal_level = replica
    # archive_mode = on
    # archive_command = 'test ! -f /backup/postgresql/wal_archive/%f && cp %p /backup/postgresql/wal_archive/%f'
    
    echo "Controllo archivi WAL..."
    local wal_count=$(ls -1 $BACKUP_DIR/wal_archive/ 2>/dev/null | wc -l)
    echo "File WAL archiviati: $wal_count"
}

#===========================================
# PULIZIA BACKUP VECCHI
#===========================================

cleanup_old_backups() {
    echo "Pulizia backup vecchi..."
    
    # Daily backups (mantieni ultimi 7 giorni)
    find $BACKUP_DIR/daily -name "*.dump" -mtime +$RETENTION_DAILY -delete
    find $BACKUP_DIR/daily -name "*.sql.gz" -mtime +$RETENTION_DAILY -delete
    
    # Weekly backups (mantieni 30 giorni)
    find $BACKUP_DIR/weekly -name "*.dump" -mtime +$RETENTION_WEEKLY -delete
    
    # Monthly backups (mantieni 1 anno)
    find $BACKUP_DIR/monthly -name "*.dump" -mtime +$RETENTION_MONTHLY -delete
    
    # WAL archives (mantieni 7 giorni)
    find $BACKUP_DIR/wal_archive -name "*.gz" -mtime +7 -delete
    
    echo "Pulizia completata"
}

#===========================================
# ESECUZIONE BACKUP
#===========================================

# Pre-check
check_disk_space
test_connection

# Backup giornaliero
backup_logical "daily" "daily"

# Backup settimanale (domenica)
if [ "$DAY" = "Sunday" ]; then
    echo "Esecuzione backup settimanale..."
    backup_logical "weekly" "weekly"
fi

# Backup mensile (primo del mese)
if [ $(date +%d) = "01" ]; then
    echo "Esecuzione backup mensile..."
    backup_logical "monthly" "monthly"
fi

# Backup configurazioni
backup_globals
backup_schema

# Setup WAL
setup_wal_archiving

# Pulizia
cleanup_old_backups

#===========================================
# STATISTICHE FINALI
#===========================================

echo "========================================="
echo "Statistiche Backup:"
echo "-----------------------------------------"
echo "Spazio totale backup: $(du -sh $BACKUP_DIR | cut -f1)"
echo "Backup giornalieri: $(ls -1 $BACKUP_DIR/daily/*.dump 2>/dev/null | wc -l)"
echo "Backup settimanali: $(ls -1 $BACKUP_DIR/weekly/*.dump 2>/dev/null | wc -l)"
echo "Backup mensili: $(ls -1 $BACKUP_DIR/monthly/*.dump 2>/dev/null | wc -l)"
echo "========================================="
echo "Backup completato: $(date)"
echo "========================================="

# Notifica successo
send_notification "Backup PostgreSQL Completato" "Backup eseguito con successo alle $(date)"

exit 0