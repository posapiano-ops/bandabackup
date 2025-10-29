#!/bin/bash
# Script ripristino backup crittografato
# Salvare come: /usr/local/bin/restore_encrypted_backup.sh

#===========================================
# CONFIGURAZIONE
#===========================================
BACKUP_ROOT="/backup"
RESTORE_LOG="/var/log/restore_encrypted_$(date +%Y%m%d_%H%M%S).log"

# Carica configurazione
if [ -f /etc/backup_encryption.conf ]; then
    source /etc/backup_encryption.conf
else
    echo "ERRORE: File configurazione non trovato"
    exit 1
fi

# Logging
exec 1> >(tee -a "$RESTORE_LOG")
exec 2>&1

echo "========================================="
echo "RIPRISTINO BACKUP CRITTOGRAFATO"
echo "Data: $(date)"
echo "Metodo: $ENCRYPTION_METHOD"
echo "========================================="

#===========================================
# FUNZIONI DECRITTOGRAFIA
#===========================================

decrypt_with_gpg() {
    local encrypted_file=$1
    local output_file=$2
    
    echo "Decrittografia GPG: $(basename $encrypted_file)..."
    
    # Decrittografia con output
    if [ -n "$output_file" ]; then
        gpg --decrypt \
            --batch \
            --yes \
            --output "$output_file" \
            "$encrypted_file" 2>/dev/null
    else
        # Decrittografia su stdout (per pipe)
        gpg --decrypt \
            --batch \
            --yes \
            --quiet \
            "$encrypted_file" 2>/dev/null
    fi
    
    return $?
}

decrypt_with_openssl() {
    local encrypted_file=$1
    local output_file=$2
    
    echo "Decrittografia OpenSSL: $(basename $encrypted_file)..."
    
    if [ ! -f "$PASSPHRASE_FILE" ]; then
        echo "ERRORE: File passphrase non trovato"
        return 1
    fi
    
    if [ -n "$output_file" ]; then
        openssl enc -d -aes-256-cbc \
            -pbkdf2 \
            -in "$encrypted_file" \
            -out "$output_file" \
            -pass file:"$PASSPHRASE_FILE"
    else
        openssl enc -d -aes-256-cbc \
            -pbkdf2 \
            -in "$encrypted_file" \
            -pass file:"$PASSPHRASE_FILE"
    fi
    
    return $?
}

decrypt_with_age() {
    local encrypted_file=$1
    local output_file=$2
    local age_key="/root/.age_private_key.txt"
    
    echo "Decrittografia age: $(basename $encrypted_file)..."
    
    if [ ! -f "$age_key" ]; then
        echo "ERRORE: Chiave age non trovata"
        return 1
    fi
    
    if [ -n "$output_file" ]; then
        age -d -i "$age_key" \
            -o "$output_file" \
            "$encrypted_file"
    else
        age -d -i "$age_key" \
            "$encrypted_file"
    fi
    
    return $?
}

# Wrapper decrittografia
decrypt_file() {
    local encrypted_file=$1
    local output_file=$2
    
    # Rileva formato da estensione
    if [[ "$encrypted_file" == *.gpg ]]; then
        decrypt_with_gpg "$encrypted_file" "$output_file"
    elif [[ "$encrypted_file" == *.enc ]]; then
        decrypt_with_openssl "$encrypted_file" "$output_file"
    elif [[ "$encrypted_file" == *.age ]]; then
        decrypt_with_age "$encrypted_file" "$output_file"
    else
        echo "ERRORE: Formato file non riconosciuto"
        return 1
    fi
}

#===========================================
# LISTA BACKUP DISPONIBILI
#===========================================

list_encrypted_backups() {
    echo ""
    echo "========================================="
    echo "BACKUP CRITTOGRAFATI DISPONIBILI"
    echo "========================================="
    
    echo ""
    echo "Backup PostgreSQL:"
    echo "------------------"
    find $BACKUP_ROOT/postgresql/encrypted/daily -type f \( -name "*.gpg" -o -name "*.enc" -o -name "*.age" \) -printf '%T@ %Tc %p\n' 2>/dev/null | sort -rn | head -10 | awk '{$1=""; print $0}'
    
    echo ""
    echo "Backup settimanali:"
    echo "-------------------"
    find $BACKUP_ROOT/postgresql/encrypted/weekly -type f \( -name "*.gpg" -o -name "*.enc" -o -name "*.age" \) -printf '%T@ %Tc %p\n' 2>/dev/null | sort -rn | head -5 | awk '{$1=""; print $0}'
    
    echo ""
    echo "Backup mensili:"
    echo "---------------"
    find $BACKUP_ROOT/postgresql/encrypted/monthly -type f \( -name "*.gpg" -o -name "*.enc" -o -name "*.age" \) -printf '%T@ %Tc %p\n' 2>/dev/null | sort -rn | head -5 | awk '{$1=""; print $0}'
    echo ""
}

#===========================================
# SELEZIONE BACKUP
#===========================================

select_backup_file() {
    list_encrypted_backups
    
    echo "Inserisci percorso completo del backup da ripristinare"
    echo "(o premi ENTER per l'ultimo backup giornaliero):"
    read -p "> " backup_path
    
    if [ -z "$backup_path" ]; then
        # Seleziona ultimo backup
        backup_path=$(find $BACKUP_ROOT/postgresql/encrypted/daily -type f \( -name "*.gpg" -o -name "*.enc" -o -name "*.age" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        
        if [ -z "$backup_path" ]; then
            echo "ERRORE: Nessun backup trovato"
            return 1
        fi
        
        echo "Selezionato: $backup_path"
    fi
    
    if [ ! -f "$backup_path" ]; then
        echo "ERRORE: File non trovato: $backup_path"
        return 1
    fi
    
    SELECTED_BACKUP="$backup_path"
    return 0
}

#===========================================
# RIPRISTINO DIRETTO (PIPE)
#===========================================

restore_direct_pipe() {
    local encrypted_file=$1
    local database=$2
    
    echo ""
    echo "========================================="
    echo "RIPRISTINO DIRETTO (PIPE)"
    echo "========================================="
    echo "File: $(basename $encrypted_file)"
    echo "Database: $database"
    echo ""
    
    read -p "ATTENZIONE: Il database sarà sovrascritto! Continuare? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Ripristino annullato"
        return 1
    fi
    
    # Stop applicazioni che usano il database
    echo "Ferma le applicazioni che usano il database prima di continuare"
    read -p "Premi ENTER quando pronto..."
    
    # Decrittografa e ripristina in pipe
    echo "Decrittografia e ripristino in corso..."
    
    decrypt_file "$encrypted_file" | pg_restore \
        -d "$database" \
        -v \
        --clean \
        --if-exists \
        -j 4 \
        --no-owner \
        --no-acl
    
    if [ $? -eq 0 ]; then
        echo "✓ Ripristino completato con successo"
        return 0
    else
        echo "✗ Errore nel ripristino"
        return 1
    fi
}

#===========================================
# RIPRISTINO CON FILE TEMPORANEO
#===========================================

restore_with_temp_file() {
    local encrypted_file=$1
    local database=$2
    
    echo ""
    echo "========================================="
    echo "RIPRISTINO CON FILE TEMPORANEO"
    echo "========================================="
    
    # Crea file temporaneo sicuro
    local temp_file=$(mktemp -p /tmp backup_decrypt_XXXXXX.dump)
    chmod 600 "$temp_file"
    
    echo "Decrittografia in corso..."
    decrypt_file "$encrypted_file" "$temp_file"
    
    if [ $? -ne 0 ]; then
        echo "✗ Errore nella decrittografia"
        rm -f "$temp_file"
        return 1
    fi
    
    local size=$(du -h "$temp_file" | cut -f1)
    echo "✓ File decrittografato: $temp_file (${size})"
    
    # Verifica integrità
    echo "Verifica integrità backup..."
    if pg_restore -l "$temp_file" > /dev/null 2>&1; then
        echo "✓ Backup valido"
    else
        echo "✗ Backup corrotto"
        shred -vfz -n 3 "$temp_file"
        return 1
    fi
    
    # Ripristino
    echo ""
    read -p "Procedere con il ripristino in $database? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        pg_restore -d "$database" \
            -v \
            --clean \
            --if-exists \
            -j 4 \
            --no-owner \
            --no-acl \
            "$temp_file"
        
        local result=$?
    else
        echo "Ripristino annullato"
        local result=1
    fi
    
    # Cancellazione sicura file temporaneo
    echo "Cancellazione sicura file temporaneo..."
    shred -vfz -n 3 "$temp_file"
    
    if [ $result -eq 0 ]; then
        echo "✓ Ripristino completato"
        return 0
    else
        echo "✗ Ripristino fallito"
        return 1
    fi
}

#===========================================
# RIPRISTINO BACKUP SPLIT
#===========================================

restore_split_backup() {
    local split_dir=$1
    local database=$2
    
    echo ""
    echo "========================================="
    echo "RIPRISTINO BACKUP SPLIT"
    echo "========================================="
    
    if [ ! -d "$split_dir" ]; then
        echo "ERRORE: Directory non trovata"
        return 1
    fi
    
    # Verifica chunk
    local chunk_count=$(ls -1 "$split_dir"/backup_part_*.* 2>/dev/null | wc -l)
    echo "Chunk trovati: $chunk_count"
    
    if [ $chunk_count -eq 0 ]; then
        echo "ERRORE: Nessun chunk trovato"
        return 1
    fi
    
    # Mostra manifest se esiste
    if [ -f "$split_dir/manifest.txt" ]; then
        echo ""
        echo "Manifest:"
        cat "$split_dir/manifest.txt"
        echo ""
    fi
    
    read -p "Procedere con il ripristino? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        return 1
    fi
    
    # Decrittografa e unisci chunk in pipe
    echo "Decrittografia e ripristino chunk..."
    
    for chunk in "$split_dir"/backup_part_*.*; do
        echo "Elaborazione: $(basename $chunk)"
        decrypt_file "$chunk"
    done | pg_restore \
        -d "$database" \
        -v \
        --clean \
        --if-exists \
        -j 4 \
        --no-owner \
        --no-acl
    
    if [ $? -eq 0 ]; then
        echo "✓ Ripristino split completato"
        return 0
    else
        echo "✗ Errore nel ripristino"
        return 1
    fi
}

#===========================================
# ESTRAZIONE SENZA RIPRISTINO
#===========================================

extract_only() {
    local encrypted_file=$1
    local output_dir=${2:-"/tmp"}
    
    echo ""
    echo "========================================="
    echo "ESTRAZIONE BACKUP"
    echo "========================================="
    
    local output_file="$output_dir/$(basename ${encrypted_file%.*})_$(date +%Y%m%d_%H%M%S)"
    
    echo "Decrittografia in: $output_file"
    
    decrypt_file "$encrypted_file" "$output_file"
    
    if [ $? -eq 0 ]; then
        chmod 600 "$output_file"
        local size=$(du -h "$output_file" | cut -f1)
        echo "✓ File estratto: $output_file (${size})"
        echo ""
        echo "⚠ IMPORTANTE: Cancella il file dopo l'uso con:"
        echo "  shred -vfz -n 3 $output_file"
        return 0
    else
        echo "✗ Errore nell'estrazione"
        return 1
    fi
}

#===========================================
# VERIFICA BACKUP CRITTOGRAFATO
#===========================================

verify_encrypted_backup() {
    local encrypted_file=$1
    
    echo ""
    echo "========================================="
    echo "VERIFICA BACKUP CRITTOGRAFATO"
    echo "========================================="
    echo "File: $(basename $encrypted_file)"
    echo ""
    
    # Info file
    echo "Informazioni file:"
    ls -lh "$encrypted_file"
    echo ""
    
    # Verifica formato
    case "$encrypted_file" in
        *.gpg)
            echo "Formato: GPG"
            gpg --list-packets "$encrypted_file" 2>&1 | head -20
            ;;
        *.enc)
            echo "Formato: OpenSSL AES-256-CBC"
            ;;
        *.age)
            echo "Formato: age"
            ;;
    esac
    
    echo ""
    read -p "Tentare decrittografia di test? (y/n): " test_decrypt
    
    if [ "$test_decrypt" = "y" ]; then
        echo "Test decrittografia (primi 1MB)..."
        decrypt_file "$encrypted_file" | head -c 1048576 > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo "✓ Decrittografia: OK"
            
            # Test pg_restore
            echo "Test integrità PostgreSQL..."
            decrypt_file "$encrypted_file" | pg_restore -l 2>/dev/null | head -20
            
            if [ ${PIPESTATUS[1]} -eq 0 ]; then
                echo "✓ Backup PostgreSQL: VALIDO"
                echo ""
                echo "Statistiche:"
                decrypt_file "$encrypted_file" | pg_restore -l 2>/dev/null | grep -c "TABLE DATA"
                echo " tabelle trovate"
            else
                echo "✗ Backup PostgreSQL: CORROTTO o formato non valido"
            fi
        else
            echo "✗ Decrittografia: FALLITA"
            echo "Verifica chiavi/passphrase"
        fi
    fi
}

#===========================================
# MENU PRINCIPALE
#===========================================

show_menu() {
    echo ""
    echo "========================================="
    echo "MENU RIPRISTINO"
    echo "========================================="
    echo "1. Ripristino rapido (pipe) - raccomandato"
    echo "2. Ripristino con file temporaneo"
    echo "3. Ripristino backup split"
    echo "4. Solo estrazione (non ripristino)"
    echo "5. Verifica backup crittografato"
    echo "6. Lista backup disponibili"
    echo "7. Esci"
    echo "========================================="
    read -p "Scelta [1-7]: " choice
    
    case $choice in
        1)
            select_backup_file || return 1
            read -p "Nome database destinazione: " db_name
            restore_direct_pipe "$SELECTED_BACKUP" "$db_name"
            ;;
        2)
            select_backup_file || return 1
            read -p "Nome database destinazione: " db_name
            restore_with_temp_file "$SELECTED_BACKUP" "$db_name"
            ;;
        3)
            echo "Inserisci percorso directory backup split:"
            read -p "> " split_path
            read -p "Nome database destinazione: " db_name
            restore_split_backup "$split_path" "$db_name"
            ;;
        4)
            select_backup_file || return 1
            read -p "Directory output [/tmp]: " output_dir
            output_dir=${output_dir:-/tmp}
            extract_only "$SELECTED_BACKUP" "$output_dir"
            ;;
        5)
            select_backup_file || return 1
            verify_encrypted_backup "$SELECTED_BACKUP"
            ;;
        6)
            list_encrypted_backups
            show_menu
            ;;
        7)
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
# RIPRISTINO AUTOMATICO DISASTER RECOVERY
#===========================================

auto_disaster_recovery() {
    echo ""
    echo "========================================="
    echo "DISASTER RECOVERY AUTOMATICO"
    echo "========================================="
    echo ""
    echo "Questa procedura:"
    echo "1. Trova l'ultimo backup valido"
    echo "2. Lo decrittografa"
    echo "3. Ripristina automaticamente"
    echo ""
    
    read -p "Nome database da ripristinare: " db_name
    
    if [ -z "$db_name" ]; then
        echo "ERRORE: Nome database richiesto"
        return 1
    fi
    
    # Trova ultimo backup
    echo "Ricerca ultimo backup valido..."
    local backup_file=$(find $BACKUP_ROOT/postgresql/encrypted/daily -type f \( -name "*.gpg" -o -name "*.enc" -o -name "*.age" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -z "$backup_file" ]; then
        echo "ERRORE: Nessun backup trovato"
        return 1
    fi
    
    echo "Backup selezionato: $backup_file"
    local age_hours=$(( ($(date +%s) - $(stat -c %Y "$backup_file")) / 3600 ))
    echo "Età backup: $age_hours ore"
    
    # Verifica rapida
    echo "Verifica backup..."
    decrypt_file "$backup_file" | head -c 1024 > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo "✗ Backup non valido o chiavi errate"
        return 1
    fi
    
    echo "✓ Backup valido"
    echo ""
    echo "ULTIMA CONFERMA:"
    echo "  Database: $db_name"
    echo "  Backup: $(basename $backup_file)"
    echo "  Età: $age_hours ore"
    echo ""
    
    read -p "Procedere con ripristino automatico? (yes/no): " final_confirm
    
    if [ "$final_confirm" != "yes" ]; then
        echo "Ripristino annullato"
        return 1
    fi
    
    # Ripristino
    echo ""
    echo "Ripristino in corso..."
    
    # Drop e ricrea database
    echo "Preparazione database..."
    su - postgres -c "dropdb --if-exists $db_name"
    su - postgres -c "createdb $db_name"
    
    # Ripristino dati
    decrypt_file "$backup_file" | pg_restore \
        -d "$db_name" \
        -v \
        -j 4 \
        --no-owner \
        --no-acl
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓✓✓ DISASTER RECOVERY COMPLETATO ✓✓✓"
        echo ""
        echo "Verifica applicazioni e servizi"
        return 0
    else
        echo ""
        echo "✗✗✗ DISASTER RECOVERY FALLITO ✗✗✗"
        echo "Controlla i log per dettagli"
        return 1
    fi
}

#===========================================
# RECUPERO CHIAVI BACKUP
#===========================================

recover_keys_from_backup() {
    echo ""
    echo "========================================="
    echo "RECUPERO CHIAVI DA BACKUP"
    echo "========================================="
    echo ""
    echo "Questa funzione ripristina le chiavi di crittografia"
    echo "da un backup esterno (USB, storage remoto, ecc.)"
    echo ""
    
    read -p "Percorso backup chiavi: " keys_path
    
    if [ ! -d "$keys_path" ]; then
        echo "ERRORE: Percorso non valido"
        return 1
    fi
    
    # Verifica checksum se presente
    if [ -f "$keys_path/CHECKSUMS.txt" ]; then
        echo "Verifica checksum..."
        cd "$keys_path"
        if sha256sum -c CHECKSUMS.txt > /dev/null 2>&1; then
            echo "✓ Checksum validi"
        else
            echo "⚠ ATTENZIONE: Checksum non validi!"
            read -p "Continuare comunque? (y/n): " continue_anyway
            if [ "$continue_anyway" != "y" ]; then
                return 1
            fi
        fi
        cd - > /dev/null
    fi
    
    # Backup chiavi correnti
    if [ -d /root/backup_keys ]; then
        echo "Backup chiavi correnti..."
        mv /root/backup_keys /root/backup_keys.old_$(date +%Y%m%d_%H%M%S)
    fi
    
    # Ripristina chiavi
    echo "Ripristino chiavi..."
    
    mkdir -p /root/backup_keys
    cp -r "$keys_path"/* /root/backup_keys/ 2>/dev/null
    
    # Ripristina file specifici
    [ -f "$keys_path/.backup_passphrase" ] && cp "$keys_path/.backup_passphrase" /root/
    [ -f "$keys_path/.age_private_key.txt" ] && cp "$keys_path/.age_private_key.txt" /root/
    [ -f "$keys_path/.age_public_key.txt" ] && cp "$keys_path/.age_public_key.txt" /root/
    
    # Import GPG se presente
    if [ -f "$keys_path/gpg_private_key.asc" ]; then
        echo "Import chiave GPG..."
        gpg --import "$keys_path/gpg_private_key.asc"
    fi
    
    # Imposta permessi
    chmod 600 /root/.backup_passphrase 2>/dev/null
    chmod 600 /root/.age_private_key.txt 2>/dev/null
    chmod 400 /root/.age_public_key.txt 2>/dev/null
    chmod -R 600 /root/backup_keys/* 2>/dev/null
    
    echo "✓ Chiavi ripristinate"
    echo ""
    echo "Test chiavi..."
    /usr/local/bin/test_encryption.sh
    
    if [ $? -eq 0 ]; then
        echo "✓ Chiavi funzionanti"
        return 0
    else
        echo "✗ Problema con le chiavi ripristinate"
        return 1
    fi
}

#===========================================
# REPORT RIPRISTINO
#===========================================

generate_restore_report() {
    local backup_file=$1
    local database=$2
    local status=$3
    
    cat << EOF

========================================
REPORT RIPRISTINO
========================================
Data: $(date)
Hostname: $(hostname)
User: $(whoami)

BACKUP:
-------
File: $backup_file
Dimensione: $(du -h "$backup_file" 2>/dev/null | cut -f1)
Età: $(( ($(date +%s) - $(stat -c %Y "$backup_file" 2>/dev/null || echo 0)) / 3600 )) ore
Metodo crittografia: $ENCRYPTION_METHOD

DATABASE:
---------
Nome: $database
Status: $status

VERIFICA:
---------
Tabelle ripristinate: $(su - postgres -c "psql -d $database -c '\dt'" 2>/dev/null | grep -c "public |")
Dimensione DB: $(su - postgres -c "psql -d $database -c \"SELECT pg_size_pretty(pg_database_size('$database'))\"" 2>/dev/null | grep -v pg_size | grep -v row | tr -d ' ')

CONNETTIVITÀ:
-------------
$(su - postgres -c "psql -d $database -c 'SELECT version()'" 2>/dev/null | head -3)

LOG FILE:
---------
$RESTORE_LOG

========================================
EOF
}

#===========================================
# PULIZIA POST-RIPRISTINO
#===========================================

cleanup_after_restore() {
    echo ""
    echo "Pulizia post-ripristino..."
    
    # Rimuovi file temporanei
    shred -vfz -n 3 /tmp/backup_decrypt_*.dump 2>/dev/null
    shred -vfz -n 3 /tmp/pg_backup_* 2>/dev/null
    
    # Analizza database
    read -p "Eseguire ANALYZE sul database? (y/n): " do_analyze
    if [ "$do_analyze" = "y" ]; then
        echo "Esecuzione ANALYZE..."
        su - postgres -c "psql -d $database -c 'ANALYZE VERBOSE'"
    fi
    
    # Reindex
    read -p "Eseguire REINDEX sul database? (y/n): " do_reindex
    if [ "$do_reindex" = "y" ]; then
        echo "Esecuzione REINDEX..."
        su - postgres -c "psql -d $database -c 'REINDEX DATABASE $database'"
    fi
    
    echo "✓ Pulizia completata"
}

#===========================================
# MAIN
#===========================================

# Verifica root
if [ "$EUID" -ne 0 ]; then
    echo "ERRORE: Questo script deve essere eseguito come root"
    exit 1
fi

# Verifica chiavi
case $ENCRYPTION_METHOD in
    gpg)
        if ! gpg --list-keys > /dev/null 2>&1; then
            echo "⚠ Nessuna chiave GPG trovata"
            read -p "Recuperare chiavi da backup? (y/n): " recover
            [ "$recover" = "y" ] && recover_keys_from_backup
        fi
        ;;
    openssl)
        if [ ! -f "$PASSPHRASE_FILE" ]; then
            echo "⚠ Passphrase non trovata"
            read -p "Recuperare chiavi da backup? (y/n): " recover
            [ "$recover" = "y" ] && recover_keys_from_backup
        fi
        ;;
    age)
        if [ ! -f /root/.age_private_key.txt ]; then
            echo "⚠ Chiave age non trovata"
            read -p "Recuperare chiavi da backup? (y/n): " recover
            [ "$recover" = "y" ] && recover_keys_from_backup
        fi
        ;;
esac

# Menu o modalità automatica
if [ "$1" = "--auto" ]; then
    auto_disaster_recovery
else
    show_menu
fi

# Cleanup
cleanup_after_restore

echo ""
echo "Log completo: $RESTORE_LOG"
echo ""

exit 0