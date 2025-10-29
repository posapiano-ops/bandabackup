#!/bin/bash
# Script di ripristino completo WildFly + PostgreSQL
# Salvare come: /usr/local/bin/restore_system.sh

#===========================================
# CONFIGURAZIONE
#===========================================
BACKUP_ROOT="/backup"
WILDFLY_HOME="/opt/wildfly"
POSTGRES_DATA="/var/lib/pgsql/data"
RESTORE_LOG="/var/log/restore_$(date +%Y%m%d_%H%M%S).log"

# Utenti
WILDFLY_USER="wildfly"
POSTGRES_USER="postgres"

echo "========================================="
echo "DISASTER RECOVERY - RIPRISTINO SISTEMA"
echo "Data: $(date)"
echo "========================================="
echo ""
echo "ATTENZIONE: Questo script ripristinerà completamente il sistema"
echo "Tutti i dati correnti saranno sovrascritti!"
echo ""

# Conferma utente
read -p "Sei sicuro di voler procedere? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Ripristino annullato"
    exit 0
fi

# Logging
exec 1> >(tee -a "$RESTORE_LOG")
exec 2>&1

#===========================================
# FUNZIONI
#===========================================

log_section() {
    echo ""
    echo "========================================="
    echo "$1"
    echo "========================================="
}

check_backup_exists() {
    local backup_type=$1
    local backup_path=$2
    
    if [ ! -d "$backup_path" ] && [ ! -f "$backup_path" ]; then
        echo "ERRORE: Backup $backup_type non trovato: $backup_path"
        return 1
    fi
    echo "✓ Backup $backup_type trovato"
    return 0
}

#===========================================
# SELEZIONE BACKUP DA RIPRISTINARE
#===========================================

select_backup() {
    log_section "Selezione Backup da Ripristinare"
    
    echo "Backup PostgreSQL disponibili:"
    echo "-------------------------------"
    ls -lht $BACKUP_ROOT/postgresql/daily/*.dump 2>/dev/null | head -10
    echo ""
    
    read -p "Inserisci nome file backup PostgreSQL (o ENTER per l'ultimo): " pg_backup
    
    if [ -z "$pg_backup" ]; then
        POSTGRES_BACKUP=$(find $BACKUP_ROOT/postgresql/daily -name "*.dump" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        echo "Selezionato ultimo backup: $POSTGRES_BACKUP"
    else
        POSTGRES_BACKUP="$BACKUP_ROOT/postgresql/daily/$pg_backup"
    fi
    
    if [ ! -f "$POSTGRES_BACKUP" ]; then
        echo "ERRORE: File backup non trovato!"
        exit 1
    fi
    
    echo ""
    echo "Backup WildFly disponibili:"
    echo "----------------------------"
    ls -lht $BACKUP_ROOT/wildfly/config/*.tar.gz 2>/dev/null | head -10
    echo ""
    
    read -p "Inserisci nome file backup WildFly (o ENTER per l'ultimo): " wf_backup
    
    if [ -z "$wf_backup" ]; then
        WILDFLY_BACKUP=$(find $BACKUP_ROOT/wildfly/config -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        echo "Selezionato ultimo backup: $WILDFLY_BACKUP"
    else
        WILDFLY_BACKUP="$BACKUP_ROOT/wildfly/config/$wf_backup"
    fi
    
    if [ ! -f "$WILDFLY_BACKUP" ]; then
        echo "ERRORE: File backup non trovato!"
        exit 1
    fi
}

#===========================================
# RIPRISTINO POSTGRESQL
#===========================================

restore_postgresql() {
    log_section "FASE 1: Ripristino PostgreSQL"
    
    echo "ATTENZIONE: Il database esistente sarà eliminato!"
    read -p "Continuare? (yes/no): " confirm_pg
    
    if [ "$confirm_pg" != "yes" ]; then
        echo "Ripristino PostgreSQL annullato"
        return 1
    fi
    
    # Stop PostgreSQL
    echo "Arresto PostgreSQL..."
    systemctl stop postgresql
    sleep 5
    
    # Backup del database corrente (sicurezza)
    if [ -d "$POSTGRES_DATA" ]; then
        echo "Backup dati correnti..."
        mv "$POSTGRES_DATA" "${POSTGRES_DATA}.pre_restore_$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Ricreare database cluster
    echo "Inizializzazione nuovo cluster PostgreSQL..."
    su - $POSTGRES_USER -c "initdb -D $POSTGRES_DATA"
    
    # Avvia PostgreSQL
    systemctl start postgresql
    sleep 10
    
    # Ripristina globals (ruoli, utenti)
    echo "Ripristino ruoli e utenti..."
    local globals_file=$(find $BACKUP_ROOT/postgresql/daily -name "globals_*.sql.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -f "$globals_file" ]; then
        gunzip -c "$globals_file" | su - $POSTGRES_USER -c "psql"
        echo "✓ Ruoli ripristinati"
    fi
    
    # Crea database
    DB_NAME=$(pg_restore -l "$POSTGRES_BACKUP" | grep -oP 'DATABASE - \K[^ ]+' | head -1)
    echo "Creazione database: $DB_NAME"
    su - $POSTGRES_USER -c "createdb $DB_NAME"
    
    # Ripristino dati
    echo "Ripristino dati database (questo può richiedere tempo)..."
    pg_restore -d $DB_NAME \
        -v \
        -j 4 \
        --no-owner \
        --no-acl \
        "$POSTGRES_BACKUP"
    
    if [ $? -eq 0 ]; then
        echo "✓ Database ripristinato con successo"
        
        # Verifica
        echo "Verifica ripristino..."
        su - $POSTGRES_USER -c "psql -d $DB_NAME -c '\dt'"
        
        return 0
    else
        echo "✗ ERRORE nel ripristino database"
        return 1
    fi
}

#===========================================
# RIPRISTINO POSTGRESQL CON PITR
#===========================================

restore_postgresql_pitr() {
    log_section "Ripristino Point-In-Time"
    
    read -p "Inserisci timestamp target (YYYY-MM-DD HH:MM:SS) o ENTER per ultimo backup: " target_time
    
    # Stop PostgreSQL
    systemctl stop postgresql
    
    # Ripristina backup base
    echo "Ripristino backup base..."
    local base_backup=$(find $BACKUP_ROOT/postgresql/base -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    rm -rf $POSTGRES_DATA/*
    tar -xzf "$base_backup" -C $POSTGRES_DATA
    
    # Configura recovery
    cat > $POSTGRES_DATA/recovery.signal << EOF
# Recovery configuration
EOF
    
    if [ -n "$target_time" ]; then
        cat >> $POSTGRES_DATA/postgresql.conf << EOF
restore_command = 'gunzip -c /backup/postgresql/wal_archive/%f.gz > %p'
recovery_target_time = '$target_time'
recovery_target_action = 'promote'
EOF
    else
        cat >> $POSTGRES_DATA/postgresql.conf << EOF
restore_command = 'gunzip -c /backup/postgresql/wal_archive/%f.gz > %p'
recovery_target = 'immediate'
recovery_target_action = 'promote'
EOF
    fi
    
    # Avvia recovery
    echo "Avvio recovery process..."
    chown -R $POSTGRES_USER:$POSTGRES_USER $POSTGRES_DATA
    systemctl start postgresql
    
    echo "PostgreSQL sta applicando WAL logs..."
    echo "Monitorare i log: tail -f /var/lib/pgsql/data/log/postgresql-*.log"
}

#===========================================
# RIPRISTINO WILDFLY
#===========================================

restore_wildfly() {
    log_section "FASE 2: Ripristino WildFly"
    
    echo "ATTENZIONE: La configurazione WildFly corrente sarà sovrascritta!"
    read -p "Continuare? (yes/no): " confirm_wf
    
    if [ "$confirm_wf" != "yes" ]; then
        echo "Ripristino WildFly annullato"
        return 1
    fi
    
    # Stop WildFly
    echo "Arresto WildFly..."
    systemctl stop wildfly
    sleep 5
    
    # Backup configurazione corrente
    if [ -d "$WILDFLY_HOME/standalone/configuration" ]; then
        echo "Backup configurazione corrente..."
        tar -czf "/tmp/wildfly_pre_restore_$(date +%Y%m%d_%H%M%S).tar.gz" \
            -C "$WILDFLY_HOME" \
            standalone/configuration \
            standalone/deployments
    fi
    
    # Ripristino configurazione
    echo "Ripristino configurazione..."
    tar -xzf "$WILDFLY_BACKUP" -C "$WILDFLY_HOME"
    
    # Ripristino deployments
    local deploy_backup=$(find $BACKUP_ROOT/wildfly/deployments -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -f "$deploy_backup" ]; then
        echo "Ripristino deployments..."
        tar -xzf "$deploy_backup" -C "$WILDFLY_HOME"
    fi
    
    # Ripristino moduli custom
    local modules_backup=$(find $BACKUP_ROOT/wildfly/modules -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -f "$modules_backup" ]; then
        echo "Ripristino moduli..."
        tar -xzf "$modules_backup" -C "$WILDFLY_HOME"
    fi
    
    # Ripristina permessi
    echo "Ripristino permessi..."
    chown -R $WILDFLY_USER:$WILDFLY_USER $WILDFLY_HOME
    chmod +x $WILDFLY_HOME/bin/*.sh
    
    # Riavvia WildFly
    echo "Riavvio WildFly..."
    systemctl start wildfly
    sleep 15
    
    # Verifica
    if systemctl is-active --quiet wildfly; then
        echo "✓ WildFly avviato con successo"
        
        # Mostra deployments
        echo "Deployments attivi:"
        ls -lh $WILDFLY_HOME/standalone/deployments/*.deployed 2>/dev/null
        
        return 0
    else
        echo "✗ ERRORE: WildFly non si è avviato!"
        echo "Controllare i log: $WILDFLY_HOME/standalone/log/server.log"
        return 1
    fi
}

#===========================================
# VERIFICA POST-RIPRISTINO
#===========================================

verify_restore() {
    log_section "FASE 3: Verifica Post-Ripristino"
    
    local errors=0
    
    # Verifica PostgreSQL
    echo "Verifica PostgreSQL..."
    if systemctl is-active --quiet postgresql; then
        echo "✓ PostgreSQL: ATTIVO"
        
        # Test connessione
        if su - $POSTGRES_USER -c "psql -l" > /dev/null 2>&1; then
            echo "✓ PostgreSQL: CONNESSIONE OK"
        else
            echo "✗ PostgreSQL: ERRORE CONNESSIONE"
            errors=$((errors + 1))
        fi
    else
        echo "✗ PostgreSQL: NON ATTIVO"
        errors=$((errors + 1))
    fi
    
    # Verifica WildFly
    echo "Verifica WildFly..."
    if systemctl is-active --quiet wildfly; then
        echo "✓ WildFly: ATTIVO"
        
        # Test HTTP
        sleep 10
        if curl -s http://localhost:8080 > /dev/null; then
            echo "✓ WildFly: HTTP OK"
        else
            echo "⚠ WildFly: HTTP NON RISPONDE (potrebbe essere normale se nessuna app deployata)"
        fi
    else
        echo "✗ WildFly: NON ATTIVO"
        errors=$((errors + 1))
    fi
    
    # Test connessione database da WildFly
    echo "Test connessione WildFly -> PostgreSQL..."
    if [ -f "$WILDFLY_HOME/bin/jboss-cli.sh" ]; then
        $WILDFLY_HOME/bin/jboss-cli.sh --connect \
            --command="/subsystem=datasources/data-source=*:test-connection-in-pool" \
            2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "✓ Datasource: CONNESSIONE OK"
        else
            echo "⚠ Datasource: Verifica manuale necessaria"
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        echo ""
        echo "✓✓✓ RIPRISTINO COMPLETATO CON SUCCESSO ✓✓✓"
        return 0
    else
        echo ""
        echo "✗✗✗ RIPRISTINO COMPLETATO CON ERRORI ✗✗✗"
        echo "Errori rilevati: $errors"
        return 1
    fi
}

#===========================================
# GENERAZIONE REPORT RIPRISTINO
#===========================================

generate_restore_report() {
    log_section "Report Ripristino"
    
    cat << EOF

========================================
REPORT RIPRISTINO
========================================
Data ripristino: $(date)
Hostname: $HOSTNAME

BACKUP UTILIZZATI:
------------------
PostgreSQL: $POSTGRES_BACKUP
WildFly: $WILDFLY_BACKUP

STATO SERVIZI:
--------------
PostgreSQL: $(systemctl is-active postgresql)
WildFly: $(systemctl is-active wildfly)

DATABASE:
---------
$(su - $POSTGRES_USER -c "psql -l" 2>/dev/null | head -10)

DEPLOYMENTS:
------------
$(ls -lh $WILDFLY_HOME/standalone/deployments/ 2>/dev/null)

LOG FILE:
---------
$RESTORE_LOG

AZIONI SUCCESSIVE:
------------------
1. Verificare manualmente le applicazioni
2. Testare le funzionalità critiche
3. Controllare i log:
   - PostgreSQL: /var/lib/pgsql/data/log/
   - WildFly: $WILDFLY_HOME/standalone/log/server.log
4. Verificare connessioni database
5. Testare accesso utenti

========================================
EOF
}

#===========================================
# MENU PRINCIPALE
#===========================================

show_menu() {
    echo ""
    echo "========================================="
    echo "MENU RIPRISTINO"
    echo "========================================="
    echo "1. Ripristino Completo (PostgreSQL + WildFly)"
    echo "2. Solo PostgreSQL (ultimo backup)"
    echo "3. Solo PostgreSQL (Point-in-Time Recovery)"
    echo "4. Solo WildFly"
    echo "5. Selezione manuale backup"
    echo "6. Ripristino da snapshot completo"
    echo "7. Test ripristino (non sovrascrive sistema)"
    echo "8. Esci"
    echo "========================================="
    read -p "Scelta: " choice
    
    case $choice in
        1)
            select_backup
            restore_postgresql
            restore_wildfly
            verify_restore
            generate_restore_report
            ;;
        2)
            POSTGRES_BACKUP=$(find $BACKUP_ROOT/postgresql/daily -name "*.dump" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
            restore_postgresql
            verify_restore
            generate_restore_report
            ;;
        3)
            restore_postgresql_pitr
            verify_restore
            generate_restore_report
            ;;
        4)
            WILDFLY_BACKUP=$(find $BACKUP_ROOT/wildfly/config -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
            restore_wildfly
            verify_restore
            generate_restore_report
            ;;
        5)
            select_backup
            echo "Backup selezionati. Cosa vuoi ripristinare?"
            echo "1. PostgreSQL"
            echo "2. WildFly"
            echo "3. Entrambi"
            read -p "Scelta: " restore_choice
            case $restore_choice in
                1) restore_postgresql ;;
                2) restore_wildfly ;;
                3) restore_postgresql && restore_wildfly ;;
            esac
            verify_restore
            generate_restore_report
            ;;
        6)
            restore_from_snapshot
            ;;
        7)
            test_restore
            ;;
        8)
            echo "Uscita"
            exit 0
            ;;
        *)
            echo "Scelta non valida"
            show_menu
            ;;
    esac
}

#===========================================
# RIPRISTINO DA SNAPSHOT
#===========================================

restore_from_snapshot() {
    log_section "Ripristino da Snapshot Completo"
    
    echo "Snapshot disponibili:"
    ls -lht $BACKUP_ROOT/snapshots/*.tar.gz 2>/dev/null | head -5
    echo ""
    
    read -p "Inserisci nome snapshot o ENTER per l'ultimo: " snapshot_name
    
    if [ -z "$snapshot_name" ]; then
        SNAPSHOT=$(find $BACKUP_ROOT/snapshots -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    else
        SNAPSHOT="$BACKUP_ROOT/snapshots/$snapshot_name"
    fi
    
    if [ ! -f "$SNAPSHOT" ]; then
        echo "ERRORE: Snapshot non trovato!"
        return 1
    fi
    
    echo "Ripristino da: $SNAPSHOT"
    echo "ATTENZIONE: Questo sovrascriverà TUTTI i backup correnti!"
    read -p "Continuare? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        return 1
    fi
    
    # Estrai snapshot
    echo "Estrazione snapshot..."
    tar -xzf "$SNAPSHOT" -C "$BACKUP_ROOT"
    
    if [ $? -eq 0 ]; then
        echo "✓ Snapshot estratto con successo"
        echo "Ora puoi procedere con il ripristino normale"
        show_menu
    else
        echo "✗ Errore nell'estrazione dello snapshot"
        return 1
    fi
}

#===========================================
# TEST RIPRISTINO (NON DISTRUTTIVO)
#===========================================

test_restore() {
    log_section "Test Ripristino (Simulazione)"
    
    TEST_DIR="/tmp/restore_test_$(date +%Y%m%d_%H%M%S)"
    mkdir -p $TEST_DIR/{postgresql,wildfly}
    
    echo "Directory test: $TEST_DIR"
    
    # Test PostgreSQL backup
    echo "Test ripristino PostgreSQL..."
    POSTGRES_BACKUP=$(find $BACKUP_ROOT/postgresql/daily -name "*.dump" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -f "$POSTGRES_BACKUP" ]; then
        # Verifica leggibilità
        if pg_restore -l "$POSTGRES_BACKUP" > $TEST_DIR/postgresql/restore_list.txt 2>&1; then
            echo "✓ Backup PostgreSQL valido"
            echo "  - Tabelle: $(grep 'TABLE DATA' $TEST_DIR/postgresql/restore_list.txt | wc -l)"
            echo "  - Dimensione: $(du -h $POSTGRES_BACKUP | cut -f1)"
        else
            echo "✗ Backup PostgreSQL corrotto!"
        fi
    fi
    
    # Test WildFly backup
    echo "Test ripristino WildFly..."
    WILDFLY_BACKUP=$(find $BACKUP_ROOT/wildfly/config -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -f "$WILDFLY_BACKUP" ]; then
        if tar -tzf "$WILDFLY_BACKUP" > $TEST_DIR/wildfly/file_list.txt 2>&1; then
            echo "✓ Backup WildFly valido"
            echo "  - File: $(cat $TEST_DIR/wildfly/file_list.txt | wc -l)"
            echo "  - Dimensione: $(du -h $WILDFLY_BACKUP | cut -f1)"
        else
            echo "✗ Backup WildFly corrotto!"
        fi
    fi
    
    echo ""
    echo "Test completato. Report salvato in: $TEST_DIR"
    echo "Rimuovere directory con: rm -rf $TEST_DIR"
}

#===========================================
# ROLLBACK
#===========================================

rollback_restore() {
    log_section "Rollback Ripristino"
    
    echo "Ricerca backup pre-ripristino..."
    
    # PostgreSQL
    POSTGRES_ROLLBACK=$(ls -t ${POSTGRES_DATA}.pre_restore_* 2>/dev/null | head -1)
    if [ -n "$POSTGRES_ROLLBACK" ]; then
        echo "Trovato backup PostgreSQL: $POSTGRES_ROLLBACK"
        read -p "Ripristinare? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            systemctl stop postgresql
            rm -rf $POSTGRES_DATA
            mv $POSTGRES_ROLLBACK $POSTGRES_DATA
            systemctl start postgresql
            echo "✓ PostgreSQL rollback completato"
        fi
    fi
    
    # WildFly
    WILDFLY_ROLLBACK=$(ls -t /tmp/wildfly_pre_restore_*.tar.gz 2>/dev/null | head -1)
    if [ -n "$WILDFLY_ROLLBACK" ]; then
        echo "Trovato backup WildFly: $WILDFLY_ROLLBACK"
        read -p "Ripristinare? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            systemctl stop wildfly
            tar -xzf "$WILDFLY_ROLLBACK" -C "$WILDFLY_HOME"
            systemctl start wildfly
            echo "✓ WildFly rollback completato"
        fi
    fi
}

#===========================================
# ESECUZIONE PRINCIPALE
#===========================================

# Verifica permessi root
if [ "$EUID" -ne 0 ]; then
    echo "ERRORE: Questo script deve essere eseguito come root"
    exit 1
fi

# Verifica esistenza backup
if [ ! -d "$BACKUP_ROOT" ]; then
    echo "ERRORE: Directory backup non trovata: $BACKUP_ROOT"
    exit 1
fi

# Mostra menu
show_menu

echo ""
echo "Log completo salvato in: $RESTORE_LOG"
echo ""

exit 0