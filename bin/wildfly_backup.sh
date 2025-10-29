#!/bin/bash
# Script completo di backup WildFly
# Salvare come: /usr/local/bin/wildfly_backup.sh

#===========================================
# CONFIGURAZIONE
#===========================================
WILDFLY_HOME="/opt/wildfly"
BACKUP_DIR="/backup/wildfly"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=14

# Configurazione WildFly CLI (opzionale per backup a caldo)
JBOSS_CLI="$WILDFLY_HOME/bin/jboss-cli.sh"
WILDFLY_USER="admin"
WILDFLY_PASS="password"
WILDFLY_HOST="localhost"
WILDFLY_PORT="9990"

# Email notifiche
ADMIN_EMAIL="admin@example.com"

# Log
LOG_DIR="/var/log/wildfly_backup"
mkdir -p $LOG_DIR
LOG_FILE="$LOG_DIR/backup_${DATE}.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "========================================="
echo "Backup WildFly iniziato: $(date)"
echo "========================================="

#===========================================
# FUNZIONI
#===========================================

send_notification() {
    local subject="$1"
    local message="$2"
    echo "$message" | mail -s "$subject" $ADMIN_EMAIL
}

check_wildfly_status() {
    if systemctl is-active --quiet wildfly; then
        echo "WildFly: RUNNING"
        return 0
    else
        echo "WildFly: STOPPED"
        return 1
    fi
}

#===========================================
# 1. BACKUP CONFIGURAZIONE
#===========================================

backup_configuration() {
    echo "Backup configurazioni WildFly..."
    
    local config_backup="$BACKUP_DIR/config/config_${DATE}.tar.gz"
    mkdir -p "$BACKUP_DIR/config"
    
    # Backup configurazioni standalone o domain
    tar -czf "$config_backup" \
        -C "$WILDFLY_HOME" \
        standalone/configuration \
        domain/configuration \
        standalone/deployments \
        domain/deployments \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "Configurazioni salvate: $config_backup"
    else
        echo "AVVISO: Alcune directory potrebbero non esistere (normale per standalone/domain)"
    fi
    
    # Backup separato delle configurazioni XML principali
    local xml_backup="$BACKUP_DIR/config/xml_${DATE}"
    mkdir -p "$xml_backup"
    
    cp -p "$WILDFLY_HOME"/standalone/configuration/*.xml "$xml_backup/" 2>/dev/null
    cp -p "$WILDFLY_HOME"/domain/configuration/*.xml "$xml_backup/" 2>/dev/null
    
    tar -czf "${xml_backup}.tar.gz" -C "$BACKUP_DIR/config" "$(basename $xml_backup)"
    rm -rf "$xml_backup"
    
    echo "Backup configurazione completato"
}

#===========================================
# 2. BACKUP DEPLOYMENTS
#===========================================

backup_deployments() {
    echo "Backup applicazioni deployate..."
    
    local deploy_backup="$BACKUP_DIR/deployments/deployments_${DATE}.tar.gz"
    mkdir -p "$BACKUP_DIR/deployments"
    
    # Backup di tutte le applicazioni deployate
    tar -czf "$deploy_backup" \
        -C "$WILDFLY_HOME" \
        --exclude='*.isdeploying' \
        --exclude='*.dodeploy' \
        --exclude='*.deployed' \
        --exclude='*.failed' \
        --exclude='*.undeployed' \
        standalone/deployments/*.war \
        standalone/deployments/*.ear \
        standalone/deployments/*.jar \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "$deploy_backup" | cut -f1)
        echo "Deployments salvati: $deploy_backup (${size})"
    else
        echo "Nessun deployment trovato o errore nel backup"
    fi
}

#===========================================
# 3. BACKUP MODULI PERSONALIZZATI
#===========================================

backup_modules() {
    echo "Backup moduli personalizzati..."
    
    local modules_backup="$BACKUP_DIR/modules/modules_${DATE}.tar.gz"
    mkdir -p "$BACKUP_DIR/modules"
    
    # Backup dei moduli custom (es. driver JDBC, librerie)
    if [ -d "$WILDFLY_HOME/modules/system/layers/base" ]; then
        tar -czf "$modules_backup" \
            -C "$WILDFLY_HOME" \
            modules/org \
            modules/com \
            2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "Moduli salvati: $modules_backup"
        fi
    fi
}

#===========================================
# 4. BACKUP DATA DIRECTORY
#===========================================

backup_data() {
    echo "Backup data directory..."
    
    local data_backup="$BACKUP_DIR/data/data_${DATE}.tar.gz"
    mkdir -p "$BACKUP_DIR/data"
    
    # Backup di log, tmp e data
    tar -czf "$data_backup" \
        -C "$WILDFLY_HOME" \
        --exclude='standalone/log/*.log' \
        standalone/data \
        standalone/tmp \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "Data directory salvata: $data_backup"
    fi
}

#===========================================
# 5. BACKUP LOG FILES
#===========================================

backup_logs() {
    echo "Backup log files..."
    
    local logs_backup="$BACKUP_DIR/logs/logs_${DATE}.tar.gz"
    mkdir -p "$BACKUP_DIR/logs"
    
    # Backup ultimi 7 giorni di log
    find "$WILDFLY_HOME/standalone/log" -name "*.log" -mtime -7 \
        -exec tar -czf "$logs_backup" {} + 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "Logs salvati: $logs_backup"
    fi
}

#===========================================
# 6. EXPORT CONFIGURAZIONE VIA CLI
#===========================================

backup_via_cli() {
    echo "Export configurazione via JBoss CLI..."
    
    if ! check_wildfly_status; then
        echo "WildFly non attivo, skip backup CLI"
        return
    fi
    
    local cli_backup="$BACKUP_DIR/cli_export/export_${DATE}"
    mkdir -p "$cli_backup"
    
    # Connessione e export datasources
    $JBOSS_CLI --connect \
        --controller=$WILDFLY_HOST:$WILDFLY_PORT \
        --user=$WILDFLY_USER \
        --password=$WILDFLY_PASS \
        --command="/subsystem=datasources:read-resource(recursive=true)" \
        > "$cli_backup/datasources.txt" 2>/dev/null
    
    # Export deployment info
    $JBOSS_CLI --connect \
        --controller=$WILDFLY_HOST:$WILDFLY_PORT \
        --user=$WILDFLY_USER \
        --password=$WILDFLY_PASS \
        --command="deployment-info" \
        > "$cli_backup/deployments_info.txt" 2>/dev/null
    
    # Comprimi export
    tar -czf "${cli_backup}.tar.gz" -C "$BACKUP_DIR/cli_export" "$(basename $cli_backup)"
    rm -rf "$cli_backup"
    
    echo "Export CLI completato"
}

#===========================================
# 7. BACKUP COMPLETO SNAPSHOT
#===========================================

backup_full_snapshot() {
    echo "Creazione snapshot completo WildFly..."
    
    local snapshot_backup="$BACKUP_DIR/snapshots/wildfly_snapshot_${DATE}.tar.gz"
    mkdir -p "$BACKUP_DIR/snapshots"
    
    # Se WildFly è attivo, considera di fermarlo per snapshot consistente
    local was_running=false
    if check_wildfly_status; then
        was_running=true
        echo "ATTENZIONE: Creazione snapshot con WildFly attivo"
        echo "Per snapshot consistente, considera di fermare WildFly"
    fi
    
    # Backup completo directory WildFly (escludendo log temporanei)
    tar -czf "$snapshot_backup" \
        --exclude='standalone/log/*.log' \
        --exclude='standalone/tmp/*' \
        --exclude='domain/tmp/*' \
        -C "$(dirname $WILDFLY_HOME)" \
        "$(basename $WILDFLY_HOME)"
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "$snapshot_backup" | cut -f1)
        echo "Snapshot completo creato: $snapshot_backup (${size})"
    fi
}

#===========================================
# 8. VERIFICA BACKUP
#===========================================

verify_backups() {
    echo "Verifica integrità backup..."
    
    local errors=0
    
    # Verifica file tar.gz
    for backup_file in $(find $BACKUP_DIR -name "*.tar.gz" -mtime -1); do
        if tar -tzf "$backup_file" > /dev/null 2>&1; then
            echo "OK: $(basename $backup_file)"
        else
            echo "ERRORE: $(basename $backup_file) è corrotto!"
            errors=$((errors + 1))
        fi
    done
    
    if [ $errors -gt 0 ]; then
        send_notification "Backup WildFly - File Corrotti" "$errors file di backup sono corrotti"
        return 1
    fi
    
    echo "Verifica completata: tutti i backup sono integri"
    return 0
}

#===========================================
# 9. PULIZIA BACKUP VECCHI
#===========================================

cleanup_old_backups() {
    echo "Pulizia backup vecchi..."
    
    # Mantieni backup per numero giorni specificato
    find $BACKUP_DIR/config -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
    find $BACKUP_DIR/deployments -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
    find $BACKUP_DIR/modules -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
    find $BACKUP_DIR/data -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
    find $BACKUP_DIR/logs -name "*.tar.gz" -mtime +30 -delete  # Log: 30 giorni
    find $BACKUP_DIR/cli_export -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
    
    # Snapshot: mantieni solo ultimi 3
    ls -t $BACKUP_DIR/snapshots/*.tar.gz 2>/dev/null | tail -n +4 | xargs -r rm
    
    echo "Pulizia completata"
}

#===========================================
# ESECUZIONE BACKUP
#===========================================

# Crea struttura directory
mkdir -p $BACKUP_DIR/{config,deployments,modules,data,logs,cli_export,snapshots}

# Esegui backup componenti
backup_configuration
backup_deployments
backup_modules
backup_data
backup_logs
backup_via_cli

# Snapshot completo (opzionale, commentare se troppo grande)
# backup_full_snapshot

# Verifica e pulizia
verify_backups
cleanup_old_backups

#===========================================
# STATISTICHE FINALI
#===========================================

echo "========================================="
echo "Statistiche Backup WildFly:"
echo "-----------------------------------------"
echo "Spazio totale backup: $(du -sh $BACKUP_DIR | cut -f1)"
echo "Configurazioni: $(ls -1 $BACKUP_DIR/config/*.tar.gz 2>/dev/null | wc -l)"
echo "Deployments: $(ls -1 $BACKUP_DIR/deployments/*.tar.gz 2>/dev/null | wc -l)"
echo "Moduli: $(ls -1 $BACKUP_DIR/modules/*.tar.gz 2>/dev/null | wc -l)"
echo "Data: $(ls -1 $BACKUP_DIR/data/*.tar.gz 2>/dev/null | wc -l)"
echo "========================================="
echo "Backup completato: $(date)"
echo "========================================="

send_notification "Backup WildFly Completato" "Backup eseguito con successo alle $(date)"

exit 0