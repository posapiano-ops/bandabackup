#!/bin/bash
# Script Master per backup coordinato WildFly + PostgreSQL
# Salvare come: /usr/local/bin/master_backup.sh

#===========================================
# CONFIGURAZIONE
#===========================================
WILDFLY_HOME="/opt/wildfly"
BACKUP_ROOT="/backup"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_DIR="/var/log/master_backup"
REMOTE_BACKUP_SERVER="backup-server.example.com"
REMOTE_BACKUP_USER="backup"
REMOTE_BACKUP_PATH="/backup/production"

# Email
ADMIN_EMAIL="admin@example.com"

# Script individuali
POSTGRES_BACKUP="/usr/local/bin/postgres_backup.sh"
WILDFLY_BACKUP="/usr/local/bin/wildfly_backup.sh"

# Setup logging
mkdir -p $LOG_DIR
LOG_FILE="$LOG_DIR/master_${DATE}.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "========================================="
echo "BACKUP MASTER INIZIATO"
echo "Data: $(date)"
echo "========================================="

#===========================================
# FUNZIONI
#===========================================

send_notification() {
    local subject="$1"
    local message="$2"
    echo "$message" | mail -s "[$HOSTNAME] $subject" $ADMIN_EMAIL
}

log_section() {
    echo ""
    echo "========================================="
    echo "$1"
    echo "========================================="
}

check_prerequisites() {
    log_section "Verifica Prerequisiti"
    
    # Verifica script esistenti
    if [ ! -f "$POSTGRES_BACKUP" ]; then
        echo "ERRORE: Script PostgreSQL non trovato: $POSTGRES_BACKUP"
        exit 1
    fi
    
    if [ ! -f "$WILDFLY_BACKUP" ]; then
        echo "ERRORE: Script WildFly non trovato: $WILDFLY_BACKUP"
        exit 1
    fi
    
    # Verifica spazio disco
    local required_gb=20
    local available=$(df -BG $BACKUP_ROOT | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ "$available" -lt "$required_gb" ]; then
        echo "ERRORE: Spazio disco insufficiente"
        send_notification "Backup Failed - Low Disk Space" "Disponibili: ${available}GB"
        exit 1
    fi
    
    echo "Prerequisiti OK - Spazio disponibile: ${available}GB"
}

#===========================================
# FASE 1: BACKUP DATABASE
#===========================================

backup_database() {
    log_section "FASE 1: Backup PostgreSQL"
    
    if [ -x "$POSTGRES_BACKUP" ]; then
        $POSTGRES_BACKUP
        
        if [ $? -eq 0 ]; then
            echo "✓ Backup PostgreSQL completato con successo"
            return 0
        else
            echo "✗ Backup PostgreSQL fallito"
            send_notification "Backup Failed - PostgreSQL" "Errore nel backup del database"
            return 1
        fi
    else
        echo "✗ Script PostgreSQL non eseguibile"
        return 1
    fi
}

#===========================================
# FASE 2: BACKUP WILDFLY (OPZIONALE: CON STOP)
#===========================================

backup_wildfly_with_stop() {
    log_section "FASE 2: Backup WildFly (con stop temporaneo)"
    
    local wildfly_was_running=false
    
    # Verifica se WildFly è attivo
    if systemctl is-active --quiet wildfly; then
        wildfly_was_running=true
        echo "WildFly è attivo - arresto temporaneo per backup consistente..."
        
        # Stop WildFly
        systemctl stop wildfly
        sleep 10
        
        if systemctl is-active --quiet wildfly; then
            echo "✗ Impossibile fermare WildFly"
            return 1
        fi
        echo "✓ WildFly arrestato"
    fi
    
    # Esegui backup
    if [ -x "$WILDFLY_BACKUP" ]; then
        $WILDFLY_BACKUP
        local backup_status=$?
    else
        echo "✗ Script WildFly non eseguibile"
        local backup_status=1
    fi
    
    # Riavvia WildFly se era attivo
    if [ "$wildfly_was_running" = true ]; then
        echo "Riavvio WildFly..."
        systemctl start wildfly
        sleep 15
        
        if systemctl is-active --quiet wildfly; then
            echo "✓ WildFly riavviato con successo"
        else
            echo "✗ ERRORE: WildFly non si è riavviato!"
            send_notification "CRITICAL - WildFly Down" "WildFly non si è riavviato dopo il backup!"
            return 1
        fi
    fi
    
    if [ $backup_status -eq 0 ]; then
        echo "✓ Backup WildFly completato con successo"
        return 0
    else
        echo "✗ Backup WildFly fallito"
        return 1
    fi
}

#===========================================
# FASE 2 ALTERNATIVA: BACKUP A CALDO
#===========================================

backup_wildfly_hot() {
    log_section "FASE 2: Backup WildFly (a caldo)"
    
    if [ -x "$WILDFLY_BACKUP" ]; then
        $WILDFLY_BACKUP
        
        if [ $? -eq 0 ]; then
            echo "✓ Backup WildFly completato con successo"
            return 0
        else
            echo "✗ Backup WildFly fallito"
            return 1
        fi
    else
        echo "✗ Script WildFly non eseguibile"
        return 1
    fi
}

#===========================================
# FASE 3: CREAZIONE SNAPSHOT COMPLETO
#===========================================

create_full_snapshot() {
    log_section "FASE 3: Creazione Snapshot Completo"
    
    local snapshot_dir="$BACKUP_ROOT/snapshots"
    local snapshot_file="$snapshot_dir/full_snapshot_${DATE}.tar.gz"
    
    mkdir -p "$snapshot_dir"
    
    echo "Creazione snapshot di tutti i backup..."
    
    tar -czf "$snapshot_file" \
        -C "$BACKUP_ROOT" \
        postgresql \
        wildfly \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "$snapshot_file" | cut -f1)
        echo "✓ Snapshot creato: $snapshot_file (${size})"
        
        # Mantieni solo ultimi 7 snapshot completi
        ls -t $snapshot_dir/full_snapshot_*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm
        
        return 0
    else
        echo "✗ Errore nella creazione dello snapshot"
        return 1
    fi
}

#===========================================
# FASE 4: SINCRONIZZAZIONE REMOTA
#===========================================

sync_to_remote() {
    log_section "FASE 4: Sincronizzazione Remota"
    
    echo "Sincronizzazione backup su server remoto..."
    
    # Test connessione SSH
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes \
         $REMOTE_BACKUP_USER@$REMOTE_BACKUP_SERVER "exit" 2>/dev/null; then
        echo "✗ Impossibile connettersi al server remoto"
        return 1
    fi
    
    # Sincronizza con rsync
    rsync -avz --delete --progress \
        -e "ssh -o ConnectTimeout=30" \
        --exclude='*.tmp' \
        --exclude='*.log' \
        $BACKUP_ROOT/ \
        $REMOTE_BACKUP_USER@$REMOTE_BACKUP_SERVER:$REMOTE_BACKUP_PATH/
    
    if [ $? -eq 0 ]; then
        echo "✓ Sincronizzazione completata"
        return 0
    else
        echo "✗ Errore nella sincronizzazione"
        return 1
    fi
}

#===========================================
# FASE 5: BACKUP SU CLOUD (OPZIONALE)
#===========================================

sync_to_cloud() {
    log_section "FASE 5: Backup su Cloud Storage"
    
    # Verifica se rclone è installato
    if ! command -v rclone &> /dev/null; then
        echo "rclone non installato - skip backup cloud"
        return 0
    fi
    
    echo "Sincronizzazione su cloud storage..."
    
    # Esempio con AWS S3 (configurare rclone remote)
    rclone sync $BACKUP_ROOT/snapshots \
        remote:my-backup-bucket/production/snapshots \
        --transfers 4 \
        --checkers 8 \
        --progress \
        --log-file=$LOG_DIR/rclone_${DATE}.log
    
    if [ $? -eq 0 ]; then
        echo "✓ Backup cloud completato"
        return 0
    else
        echo "✗ Errore nel backup cloud"
        return 1
    fi
}

#===========================================
# FASE 6: VERIFICA INTEGRITÀ
#===========================================

verify_all_backups() {
    log_section "FASE 6: Verifica Integrità Backup"
    
    local errors=0
    
    echo "Verifica backup PostgreSQL..."
    local latest_pg=$(find $BACKUP_ROOT/postgresql/daily -name "*.dump" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -f "$latest_pg" ]; then
        if pg_restore -l "$latest_pg" > /dev/null 2>&1; then
            echo "✓ Backup PostgreSQL: OK"
        else
            echo "✗ Backup PostgreSQL: CORROTTO"
            errors=$((errors + 1))
        fi
    else
        echo "✗ Nessun backup PostgreSQL trovato"
        errors=$((errors + 1))
    fi
    
    echo "Verifica backup WildFly..."
    local latest_wildfly=$(find $BACKUP_ROOT/wildfly/config -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -f "$latest_wildfly" ]; then
        if tar -tzf "$latest_wildfly" > /dev/null 2>&1; then
            echo "✓ Backup WildFly: OK"
        else
            echo "✗ Backup WildFly: CORROTTO"
            errors=$((errors + 1))
        fi
    else
        echo "✗ Nessun backup WildFly trovato"
        errors=$((errors + 1))
    fi
    
    if [ $errors -gt 0 ]; then
        send_notification "Backup Verification Failed" "$errors backup corrotti o mancanti"
        return 1
    fi
    
    echo "✓ Tutti i backup sono integri"
    return 0
}

#===========================================
# FASE 7: PULIZIA E OTTIMIZZAZIONE
#===========================================

cleanup_and_optimize() {
    log_section "FASE 7: Pulizia e Ottimizzazione"
    
    echo "Pulizia file temporanei..."
    find $BACKUP_ROOT -name "*.tmp" -delete
    find $LOG_DIR -name "*.log" -mtime +30 -delete
    
    echo "Calcolo statistiche..."
    local total_size=$(du -sh $BACKUP_ROOT | cut -f1)
    local pg_size=$(du -sh $BACKUP_ROOT/postgresql 2>/dev/null | cut -f1)
    local wf_size=$(du -sh $BACKUP_ROOT/wildfly 2>/dev/null | cut -f1)
    local snap_size=$(du -sh $BACKUP_ROOT/snapshots 2>/dev/null | cut -f1)
    
    echo "Spazio totale backup: $total_size"
    echo "  - PostgreSQL: $pg_size"
    echo "  - WildFly: $wf_size"
    echo "  - Snapshots: $snap_size"
    
    # Ottimizzazione: comprimi vecchi backup
    echo "Ottimizzazione backup vecchi..."
    find $BACKUP_ROOT/postgresql/daily -name "*.dump" -mtime +7 -exec gzip -9 {} \;
    
    echo "✓ Pulizia completata"
}

#===========================================
# GENERAZIONE REPORT
#===========================================

generate_report() {
    log_section "REPORT FINALE"
    
    local report_file="$BACKUP_ROOT/reports/backup_report_${DATE}.txt"
    mkdir -p "$BACKUP_ROOT/reports"
    
    cat > "$report_file" << EOF
========================================
REPORT BACKUP - $(date)
========================================
Hostname: $HOSTNAME
Date: $DATE

STATO BACKUP:
-------------
PostgreSQL: $([ -f "$BACKUP_ROOT/postgresql/last_successful_backup.txt" ] && echo "✓ OK" || echo "✗ FAILED")
WildFly: $([ -d "$BACKUP_ROOT/wildfly/config" ] && echo "✓ OK" || echo "✗ FAILED")
Snapshot: $([ -d "$BACKUP_ROOT/snapshots" ] && echo "✓ OK" || echo "✗ FAILED")
Sync Remoto: $([ $? -eq 0 ] && echo "✓ OK" || echo "✗ FAILED")

DIMENSIONI:
-----------
Totale: $(du -sh $BACKUP_ROOT | cut -f1)
PostgreSQL: $(du -sh $BACKUP_ROOT/postgresql 2>/dev/null | cut -f1)
WildFly: $(du -sh $BACKUP_ROOT/wildfly 2>/dev/null | cut -f1)
Snapshots: $(du -sh $BACKUP_ROOT/snapshots 2>/dev/null | cut -f1)

FILE RECENTI:
-------------
Ultimo backup PostgreSQL:
$(find $BACKUP_ROOT/postgresql/daily -name "*.dump" -type f -printf '%T+ %p\n' | sort | tail -1)

Ultimo backup WildFly:
$(find $BACKUP_ROOT/wildfly/config -name "*.tar.gz" -type f -printf '%T+ %p\n' | sort | tail -1)

Ultimo snapshot:
$(find $BACKUP_ROOT/snapshots -name "*.tar.gz" -type f -printf '%T+ %p\n' | sort | tail -1)

SPAZIO DISCO:
-------------
$(df -h $BACKUP_ROOT)

LOG FILE:
---------
$LOG_FILE

========================================
EOF
    
    cat "$report_file"
    
    # Invia report via email
    mail -s "[$HOSTNAME] Backup Report - $(date +%Y-%m-%d)" $ADMIN_EMAIL < "$report_file"
    
    # Mantieni solo ultimi 30 report
    find $BACKUP_ROOT/reports -name "backup_report_*.txt" -mtime +30 -delete
}

#===========================================
# ESECUZIONE PRINCIPALE
#===========================================

main() {
    local start_time=$(date +%s)
    local exit_code=0
    
    # Prerequisiti
    check_prerequisites || exit 1
    
    # FASE 1: Database
    if ! backup_database; then
        echo "ERRORE CRITICO: Backup database fallito"
        exit_code=1
    fi
    
    # FASE 2: Application Server
    # Scegli una delle due opzioni:
    # backup_wildfly_with_stop  # Backup con stop (più sicuro)
    backup_wildfly_hot          # Backup a caldo (meno downtime)
    
    if [ $? -ne 0 ]; then
        echo "ERRORE: Backup WildFly fallito"
        exit_code=1
    fi
    
    # FASE 3: Snapshot
    create_full_snapshot
    
    # FASE 4: Sync remoto
    sync_to_remote
    
    # FASE 5: Cloud (opzionale)
    # sync_to_cloud
    
    # FASE 6: Verifica
    verify_all_backups || exit_code=1
    
    # FASE 7: Pulizia
    cleanup_and_optimize
    
    # Report finale
    generate_report
    
    # Calcola durata
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    log_section "BACKUP COMPLETATO"
    echo "Durata totale: ${minutes}m ${seconds}s"
    echo "Exit code: $exit_code"
    
    if [ $exit_code -eq 0 ]; then
        send_notification "Backup Completed Successfully" "Backup completato in ${minutes}m ${seconds}s"
    else
        send_notification "Backup Completed with Errors" "Backup completato con errori - Controllare i log"
    fi
    
    exit $exit_code
}

# Trap per gestire interruzioni
trap 'echo "Backup interrotto!"; send_notification "Backup Interrupted" "Backup interrotto manualmente"; exit 130' INT TERM

# Esegui backup
main