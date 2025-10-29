#!/bin/bash
# Script backup PostgreSQL con crittografia GPG
# Salvare come: /usr/local/bin/postgres_encrypted_backup.sh

#===========================================
# CONFIGURAZIONE
#===========================================
PGHOST="localhost"
PGPORT="5432"
PGUSER="postgres"
PGDATABASE="your_database"
BACKUP_DIR="/backup/postgresql/encrypted"
LOG_DIR="/var/log/postgresql_backup"
DATE=$(date +%Y%m%d_%H%M%S)

# Configurazione crittografia
GPG_RECIPIENT="backup@example.com"  # Email chiave GPG
GPG_KEY_ID="YOUR_KEY_ID"            # ID chiave GPG (opzionale)
ENCRYPTION_METHOD="gpg"              # gpg, openssl, age
PASSPHRASE_FILE="/root/.backup_passphrase"  # Per automazione

# Retention
RETENTION_DAYS=30

# Email notifiche
ADMIN_EMAIL="admin@example.com"

# Setup
mkdir -p $BACKUP_DIR/{daily,weekly,monthly}
mkdir -p $LOG_DIR
LOG_FILE="$LOG_DIR/encrypted_backup_${DATE}.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "========================================="
echo "Backup Crittografato PostgreSQL"
echo "Data: $(date)"
echo "========================================="

#===========================================
# FUNZIONI CRITTOGRAFIA
#===========================================

# Crittografia con GPG (raccomandato)
encrypt_with_gpg() {
    local input_file=$1
    local output_file="${input_file}.gpg"
    
    echo "Crittografia GPG del backup..."
    
    # Opzione 1: Con chiave pubblica (più sicuro)
    if gpg --list-keys "$GPG_RECIPIENT" > /dev/null 2>&1; then
        gpg --encrypt \
            --recipient "$GPG_RECIPIENT" \
            --trust-model always \
            --compress-algo zlib \
            --output "$output_file" \
            "$input_file"
    
    # Opzione 2: Con passphrase simmetrica
    elif [ -f "$PASSPHRASE_FILE" ]; then
        gpg --symmetric \
            --cipher-algo AES256 \
            --passphrase-file "$PASSPHRASE_FILE" \
            --batch \
            --yes \
            --compress-algo zlib \
            --output "$output_file" \
            "$input_file"
    else
        echo "ERRORE: Nessuna chiave GPG trovata e nessuna passphrase configurata"
        return 1
    fi
    
    if [ $? -eq 0 ]; then
        # Rimuovi file non crittografato
        shred -vfz -n 3 "$input_file"
        
        local size=$(du -h "$output_file" | cut -f1)
        echo "✓ File crittografato: $output_file (${size})"
        return 0
    else
        echo "✗ Errore nella crittografia"
        return 1
    fi
}

# Crittografia con OpenSSL
encrypt_with_openssl() {
    local input_file=$1
    local output_file="${input_file}.enc"
    
    echo "Crittografia OpenSSL del backup..."
    
    if [ ! -f "$PASSPHRASE_FILE" ]; then
        echo "ERRORE: File passphrase non trovato"
        return 1
    fi
    
    openssl enc -aes-256-cbc \
        -salt \
        -pbkdf2 \
        -iter 100000 \
        -in "$input_file" \
        -out "$output_file" \
        -pass file:"$PASSPHRASE_FILE"
    
    if [ $? -eq 0 ]; then
        shred -vfz -n 3 "$input_file"
        local size=$(du -h "$output_file" | cut -f1)
        echo "✓ File crittografato: $output_file (${size})"
        return 0
    else
        echo "✗ Errore nella crittografia"
        return 1
    fi
}

# Crittografia con age (moderno, semplice)
encrypt_with_age() {
    local input_file=$1
    local output_file="${input_file}.age"
    local age_public_key="/root/.age_public_key.txt"
    
    echo "Crittografia age del backup..."
    
    if [ ! -f "$age_public_key" ]; then
        echo "ERRORE: Chiave pubblica age non trovata"
        return 1
    fi
    
    age -r "$(cat $age_public_key)" \
        -o "$output_file" \
        "$input_file"
    
    if [ $? -eq 0 ]; then
        shred -vfz -n 3 "$input_file"
        local size=$(du -h "$output_file" | cut -f1)
        echo "✓ File crittografato: $output_file (${size})"
        return 0
    else
        echo "✗ Errore nella crittografia"
        return 1
    fi
}

# Funzione wrapper per crittografia
encrypt_backup() {
    local file=$1
    
    case $ENCRYPTION_METHOD in
        gpg)
            encrypt_with_gpg "$file"
            ;;
        openssl)
            encrypt_with_openssl "$file"
            ;;
        age)
            encrypt_with_age "$file"
            ;;
        *)
            echo "ERRORE: Metodo crittografia non valido: $ENCRYPTION_METHOD"
            return 1
            ;;
    esac
}

#===========================================
# BACKUP DATABASE
#===========================================

backup_database() {
    local backup_type=$1
    local backup_subdir=$2
    
    echo "Inizio backup database ($backup_type)..."
    
    # File temporaneo non crittografato
    local temp_backup="/tmp/pg_backup_${DATE}.dump"
    
    # Backup con pg_dump
    pg_dump -h $PGHOST -p $PGPORT -U $PGUSER \
        -F c \
        -b \
        -v \
        -f "$temp_backup" \
        $PGDATABASE
    
    if [ $? -ne 0 ]; then
        echo "✗ Errore nel backup database"
        rm -f "$temp_backup"
        return 1
    fi
    
    local size=$(du -h "$temp_backup" | cut -f1)
    echo "✓ Backup creato: $temp_backup (${size})"
    
    # Sposta in directory finale
    local final_backup="$BACKUP_DIR/$backup_subdir/${PGDATABASE}_${backup_type}_${DATE}.dump"
    mv "$temp_backup" "$final_backup"
    
    # Crittografa
    encrypt_backup "$final_backup"
    
    if [ $? -eq 0 ]; then
        echo "✓ Backup crittografato completato"
        return 0
    else
        echo "✗ Errore nella crittografia"
        # Rimuovi comunque file non crittografato per sicurezza
        shred -vfz -n 3 "$final_backup" 2>/dev/null
        return 1
    fi
}

#===========================================
# BACKUP GLOBALS CRITTOGRAFATO
#===========================================

backup_globals_encrypted() {
    echo "Backup globals crittografato..."
    
    local temp_file="/tmp/globals_${DATE}.sql"
    local final_file="$BACKUP_DIR/daily/globals_${DATE}.sql"
    
    pg_dumpall -h $PGHOST -p $PGPORT -U $PGUSER \
        --globals-only \
        -f "$temp_file"
    
    if [ $? -eq 0 ]; then
        mv "$temp_file" "$final_file"
        encrypt_backup "$final_file"
        echo "✓ Globals crittografati"
    else
        rm -f "$temp_file"
        echo "✗ Errore backup globals"
    fi
}

#===========================================
# BACKUP CON SPLIT E CRITTOGRAFIA
#===========================================

backup_large_database_split() {
    echo "Backup database grande con split e crittografia..."
    
    local temp_backup="/tmp/pg_backup_${DATE}.dump"
    local split_dir="$BACKUP_DIR/daily/split_${DATE}"
    local chunk_size="500M"  # Dimensione chunk
    
    mkdir -p "$split_dir"
    
    # Backup
    pg_dump -h $PGHOST -p $PGPORT -U $PGUSER \
        -F c \
        -f "$temp_backup" \
        $PGDATABASE
    
    if [ $? -ne 0 ]; then
        echo "✗ Errore nel backup"
        rm -f "$temp_backup"
        return 1
    fi
    
    # Split in chunk
    echo "Split backup in chunk da $chunk_size..."
    split -b $chunk_size -d "$temp_backup" "$split_dir/backup_part_"
    
    # Rimuovi file originale
    shred -vfz -n 3 "$temp_backup"
    
    # Crittografa ogni chunk
    echo "Crittografia chunk..."
    for chunk in "$split_dir"/backup_part_*; do
        echo "Crittografia $(basename $chunk)..."
        encrypt_backup "$chunk"
    done
    
    # Crea file manifest
    cat > "$split_dir/manifest.txt" << EOF
Database: $PGDATABASE
Date: $(date)
Chunks: $(ls -1 $split_dir/backup_part_*.* 2>/dev/null | wc -l)
Method: $ENCRYPTION_METHOD
Restore: cat backup_part_* | gpg -d | pg_restore -d dbname
EOF
    
    echo "✓ Backup split e crittografato completato"
}

#===========================================
# VERIFICA INTEGRITÀ BACKUP CRITTOGRAFATO
#===========================================

verify_encrypted_backup() {
    local encrypted_file=$1
    
    echo "Verifica integrità backup crittografato..."
    
    case $ENCRYPTION_METHOD in
        gpg)
            # Verifica GPG (senza decrittografare completamente)
            if [ -f "${encrypted_file}.gpg" ]; then
                gpg --list-packets "${encrypted_file}.gpg" > /dev/null 2>&1
                if [ $? -eq 0 ]; then
                    echo "✓ File GPG valido: $(basename $encrypted_file).gpg"
                    return 0
                fi
            fi
            ;;
        openssl)
            # OpenSSL: prova decrittografia primi byte
            if [ -f "${encrypted_file}.enc" ]; then
                openssl enc -d -aes-256-cbc \
                    -pbkdf2 \
                    -in "${encrypted_file}.enc" \
                    -pass file:"$PASSPHRASE_FILE" \
                    2>/dev/null | head -c 1024 > /dev/null
                if [ $? -eq 0 ]; then
                    echo "✓ File OpenSSL valido: $(basename $encrypted_file).enc"
                    return 0
                fi
            fi
            ;;
        age)
            if [ -f "${encrypted_file}.age" ]; then
                # age non ha verifica senza decrittare
                echo "⚠ File age: $(basename $encrypted_file).age (verifica completa richiede decrittografia)"
                return 0
            fi
            ;;
    esac
    
    echo "✗ Verifica fallita o file non trovato"
    return 1
}

#===========================================
# CHECKSUM PER INTEGRITÀ
#===========================================

create_checksums() {
    echo "Creazione checksum per verifica integrità..."
    
    local checksum_file="$BACKUP_DIR/daily/checksums_${DATE}.sha256"
    
    find $BACKUP_DIR/daily -type f \
        -name "*${DATE}*" \
        -exec sha256sum {} \; > "$checksum_file"
    
    # Firma digitale del checksum
    if [ "$ENCRYPTION_METHOD" = "gpg" ]; then
        gpg --detach-sign \
            --armor \
            --recipient "$GPG_RECIPIENT" \
            "$checksum_file"
        echo "✓ Checksum firmato digitalmente"
    fi
    
    echo "✓ Checksum creati: $checksum_file"
}

#===========================================
# GESTIONE CHIAVI SICURA
#===========================================

backup_encryption_keys() {
    echo "Backup chiavi crittografia..."
    
    local key_backup_dir="/backup/keys_backup"
    mkdir -p "$key_backup_dir"
    
    case $ENCRYPTION_METHOD in
        gpg)
            # Export chiave GPG
            gpg --export-secret-keys --armor "$GPG_RECIPIENT" \
                > "$key_backup_dir/gpg_private_key_${DATE}.asc"
            
            # Crittografa la chiave con una passphrase diversa
            openssl enc -aes-256-cbc \
                -salt \
                -pbkdf2 \
                -in "$key_backup_dir/gpg_private_key_${DATE}.asc" \
                -out "$key_backup_dir/gpg_private_key_${DATE}.asc.enc" \
                -pass pass:"MASTER_PASSPHRASE_CHANGE_ME"
            
            # Rimuovi file non crittografato
            shred -vfz -n 3 "$key_backup_dir/gpg_private_key_${DATE}.asc"
            ;;
        age)
            # Backup chiave age
            cp /root/.age_private_key.txt "$key_backup_dir/age_key_${DATE}.txt"
            openssl enc -aes-256-cbc \
                -salt \
                -in "$key_backup_dir/age_key_${DATE}.txt" \
                -out "$key_backup_dir/age_key_${DATE}.txt.enc"
            shred -vfz -n 3 "$key_backup_dir/age_key_${DATE}.txt"
            ;;
    esac
    
    echo "⚠ IMPORTANTE: Conserva le chiavi in luogo sicuro separato!"
    echo "  Backup chiavi: $key_backup_dir"
}

#===========================================
# PULIZIA SICURA
#===========================================

secure_cleanup() {
    echo "Pulizia sicura backup vecchi..."
    
    # Trova e rimuovi file crittografati vecchi
    case $ENCRYPTION_METHOD in
        gpg)
            find $BACKUP_DIR/daily -name "*.gpg" -mtime +$RETENTION_DAYS -exec shred -vfz -n 1 {} \;
            ;;
        openssl)
            find $BACKUP_DIR/daily -name "*.enc" -mtime +$RETENTION_DAYS -exec shred -vfz -n 1 {} \;
            ;;
        age)
            find $BACKUP_DIR/daily -name "*.age" -mtime +$RETENTION_DAYS -exec shred -vfz -n 1 {} \;
            ;;
    esac
    
    # Pulizia checksum vecchi
    find $BACKUP_DIR/daily -name "checksums_*.sha256*" -mtime +$RETENTION_DAYS -delete
    
    # Pulizia file temporanei
    shred -vfz -n 3 /tmp/pg_backup_* 2>/dev/null
    shred -vfz -n 3 /tmp/globals_* 2>/dev/null
    
    echo "✓ Pulizia completata"
}

#===========================================
# ESECUZIONE PRINCIPALE
#===========================================

main() {
    local exit_code=0
    
    # Verifica prerequisiti
    echo "Verifica prerequisiti..."
    
    case $ENCRYPTION_METHOD in
        gpg)
            if ! command -v gpg &> /dev/null; then
                echo "ERRORE: GPG non installato"
                exit 1
            fi
            ;;
        openssl)
            if ! command -v openssl &> /dev/null; then
                echo "ERRORE: OpenSSL non installato"
                exit 1
            fi
            if [ ! -f "$PASSPHRASE_FILE" ]; then
                echo "ERRORE: File passphrase non trovato"
                exit 1
            fi
            ;;
        age)
            if ! command -v age &> /dev/null; then
                echo "ERRORE: age non installato"
                exit 1
            fi
            ;;
    esac
    
    # Esegui backup
    backup_database "daily" "daily"
    backup_globals_encrypted
    
    # Backup settimanale
    if [ "$(date +%A)" = "Sunday" ]; then
        backup_database "weekly" "weekly"
    fi
    
    # Backup mensile
    if [ "$(date +%d)" = "01" ]; then
        backup_database "monthly" "monthly"
    fi
    
    # Per database molto grandi
    # backup_large_database_split
    
    # Verifica integrità
    local latest_backup=$(find $BACKUP_DIR/daily -name "${PGDATABASE}_daily_${DATE}.dump" -type f 2>/dev/null | head -1)
    if [ -n "$latest_backup" ]; then
        verify_encrypted_backup "$latest_backup"
    fi
    
    # Crea checksum
    create_checksums
    
    # Backup chiavi (mensile)
    if [ "$(date +%d)" = "01" ]; then
        backup_encryption_keys
    fi
    
    # Pulizia
    secure_cleanup
    
    echo ""
    echo "========================================="
    echo "Backup crittografato completato"
    echo "Metodo: $ENCRYPTION_METHOD"
    echo "========================================="
    
    exit $exit_code
}

# Esegui
main