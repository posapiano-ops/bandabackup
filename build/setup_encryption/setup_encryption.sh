#!/bin/bash
# Setup iniziale sistema crittografia backup
# Salvare come: /usr/local/bin/setup_encryption.sh

echo "========================================="
echo "SETUP CRITTOGRAFIA BACKUP"
echo "========================================="
echo ""

#===========================================
# MENU SELEZIONE METODO
#===========================================

select_encryption_method() {
    echo "Seleziona metodo di crittografia:"
    echo "1. GPG (GnuPG) - Raccomandato per produzione"
    echo "2. OpenSSL - Semplice, basato su passphrase"
    echo "3. age - Moderno e semplice"
    echo "4. Setup tutti i metodi"
    echo ""
    read -p "Scelta [1-4]: " choice
    
    case $choice in
        1) setup_gpg ;;
        2) setup_openssl ;;
        3) setup_age ;;
        4) setup_gpg && setup_openssl && setup_age ;;
        *) echo "Scelta non valida"; exit 1 ;;
    esac
}

#===========================================
# SETUP GPG
#===========================================

setup_gpg() {
    echo ""
    echo "========================================="
    echo "SETUP GPG"
    echo "========================================="
    
    # Verifica installazione
    if ! command -v gpg &> /dev/null; then
        echo "Installazione GPG..."
        if [ -f /etc/redhat-release ]; then
            yum install -y gnupg2
        elif [ -f /etc/debian_version ]; then
            apt-get update && apt-get install -y gnupg2
        fi
    fi
    
    echo "GPG versione: $(gpg --version | head -1)"
    echo ""
    
    # Verifica chiave esistente
    if gpg --list-keys | grep -q "backup@"; then
        echo "Chiave GPG per backup già esistente."
        read -p "Creare nuova chiave? (y/n): " create_new
        if [ "$create_new" != "y" ]; then
            return 0
        fi
    fi
    
    echo "Creazione chiave GPG per backup..."
    echo ""
    
    read -p "Nome completo [Backup System]: " full_name
    full_name=${full_name:-"Backup System"}
    
    read -p "Email [backup@$(hostname)]: " email
    email=${email:-"backup@$(hostname)"}
    
    read -s -p "Passphrase per chiave: " passphrase
    echo ""
    read -s -p "Conferma passphrase: " passphrase2
    echo ""
    
    if [ "$passphrase" != "$passphrase2" ]; then
        echo "ERRORE: Le passphrase non corrispondono"
        return 1
    fi
    
    # Genera chiave
    cat > /tmp/gpg_batch << EOF
%echo Generating GPG key for backup
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $full_name
Name-Email: $email
Expire-Date: 0
Passphrase: $passphrase
%commit
%echo Done
EOF
    
    gpg --batch --generate-key /tmp/gpg_batch
    shred -vfz /tmp/gpg_batch
    
    # Ottieni key ID
    KEY_ID=$(gpg --list-keys "$email" | grep -A 1 "^pub" | tail -1 | tr -d ' ')
    
    echo ""
    echo "✓ Chiave GPG creata con successo!"
    echo "  Email: $email"
    echo "  Key ID: $KEY_ID"
    
    # Export chiavi
    echo ""
    echo "Export chiavi..."
    mkdir -p /root/backup_keys
    chmod 700 /root/backup_keys
    
    gpg --export-secret-keys --armor "$email" > /root/backup_keys/gpg_private_key.asc
    gpg --export --armor "$email" > /root/backup_keys/gpg_public_key.asc
    
    chmod 600 /root/backup_keys/*
    
    echo "✓ Chiavi esportate in: /root/backup_keys/"
    echo ""
    echo "⚠ IMPORTANTE:"
    echo "  1. Fai backup delle chiavi in luogo sicuro"
    echo "  2. Conserva la passphrase separatamente"
    echo "  3. Per automazione, salva passphrase in:"
    echo "     echo 'your_passphrase' > /root/.gpg_passphrase"
    echo "     chmod 400 /root/.gpg_passphrase"
    
    # Salva configurazione
    cat > /etc/backup_encryption.conf << EOF
# Configurazione crittografia backup
ENCRYPTION_METHOD=gpg
GPG_RECIPIENT=$email
GPG_KEY_ID=$KEY_ID
EOF
    
    chmod 600 /etc/backup_encryption.conf
}

#===========================================
# SETUP OPENSSL
#===========================================

setup_openssl() {
    echo ""
    echo "========================================="
    echo "SETUP OPENSSL"
    echo "========================================="
    
    if ! command -v openssl &> /dev/null; then
        echo "ERRORE: OpenSSL non installato"
        return 1
    fi
    
    echo "OpenSSL versione: $(openssl version)"
    echo ""
    
    # Genera passphrase forte
    echo "Generazione passphrase sicura..."
    read -p "Lunghezza passphrase [32]: " length
    length=${length:-32}
    
    # Genera passphrase casuale
    PASSPHRASE=$(openssl rand -base64 $length | tr -d '\n')
    
    # Salva passphrase
    echo "$PASSPHRASE" > /root/.backup_passphrase
    chmod 400 /root/.backup_passphrase
    
    echo "✓ Passphrase generata e salvata in: /root/.backup_passphrase"
    echo ""
    echo "⚠ IMPORTANTE:"
    echo "  Passphrase: ${PASSPHRASE:0:10}...${PASSPHRASE: -10}"
    echo "  (completa salvata in /root/.backup_passphrase)"
    echo ""
    echo "  Fai backup di questo file in luogo sicuro!"
    echo "  Per visualizzare: cat /root/.backup_passphrase"
    
    # Test crittografia
    echo ""
    echo "Test crittografia..."
    echo "Test data" > /tmp/test_encrypt.txt
    
    openssl enc -aes-256-cbc \
        -salt \
        -pbkdf2 \
        -iter 100000 \
        -in /tmp/test_encrypt.txt \
        -out /tmp/test_encrypt.enc \
        -pass file:/root/.backup_passphrase
    
    openssl enc -d -aes-256-cbc \
        -pbkdf2 \
        -iter 100000 \
        -in /tmp/test_encrypt.enc \
        -pass file:/root/.backup_passphrase \
        | grep -q "Test data"
    
    if [ $? -eq 0 ]; then
        echo "✓ Test crittografia/decrittografia: OK"
    else
        echo "✗ Test fallito"
    fi
    
    rm -f /tmp/test_encrypt.*
    
    # Salva configurazione
    cat > /etc/backup_encryption.conf << EOF
# Configurazione crittografia backup
ENCRYPTION_METHOD=openssl
PASSPHRASE_FILE=/root/.backup_passphrase
CIPHER=aes-256-cbc
PBKDF2_ITERATIONS=100000
EOF
    
    chmod 600 /etc/backup_encryption.conf
}

#===========================================
# SETUP AGE
#===========================================

setup_age() {
    echo ""
    echo "========================================="
    echo "SETUP AGE"
    echo "========================================="
    
    # Installa age se non presente
    if ! command -v age &> /dev/null; then
        echo "Installazione age..."
        
        # Download latest release
        AGE_VERSION="v1.1.1"
        wget -O /tmp/age.tar.gz \
            "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-amd64.tar.gz"
        
        tar -xzf /tmp/age.tar.gz -C /tmp/
        mv /tmp/age/age /usr/local/bin/
        mv /tmp/age/age-keygen /usr/local/bin/
        rm -rf /tmp/age*
        
        chmod +x /usr/local/bin/age*
    fi
    
    echo "age versione: $(age --version)"
    echo ""
    
    # Genera chiave
    echo "Generazione chiave age..."
    age-keygen -o /root/.age_private_key.txt
    
    if [ $? -eq 0 ]; then
        # Estrai chiave pubblica
        grep "public key:" /root/.age_private_key.txt | cut -d: -f2 | tr -d ' ' > /root/.age_public_key.txt
        
        chmod 400 /root/.age_private_key.txt
        chmod 400 /root/.age_public_key.txt
        
        echo "✓ Chiave age generata"
        echo "  Privata: /root/.age_private_key.txt"
        echo "  Pubblica: $(cat /root/.age_public_key.txt)"
        echo ""
        echo "⚠ IMPORTANTE: Fai backup della chiave privata!"
        
        # Backup chiavi
        mkdir -p /root/backup_keys
        cp /root/.age_private_key.txt /root/backup_keys/age_private_key_$(date +%Y%m%d).txt
        cp /root/.age_public_key.txt /root/backup_keys/age_public_key_$(date +%Y%m%d).txt
        chmod 600 /root/backup_keys/age_*
        
        # Test
        echo ""
        echo "Test crittografia age..."
        echo "Test data" | age -r "$(cat /root/.age_public_key.txt)" > /tmp/test.age
        age -d -i /root/.age_private_key.txt /tmp/test.age | grep -q "Test data"
        
        if [ $? -eq 0 ]; then
            echo "✓ Test crittografia/decrittografia: OK"
        fi
        rm -f /tmp/test.age
    fi
    
    # Salva configurazione
    cat > /etc/backup_encryption.conf << EOF
# Configurazione crittografia backup
ENCRYPTION_METHOD=age
AGE_PUBLIC_KEY_FILE=/root/.age_public_key.txt
AGE_PRIVATE_KEY_FILE=/root/.age_private_key.txt
EOF
    
    chmod 600 /etc/backup_encryption.conf
}

#===========================================
# SETUP KEY ROTATION
#===========================================

setup_key_rotation() {
    echo ""
    echo "========================================="
    echo "SETUP KEY ROTATION"
    echo "========================================="
    
    cat > /usr/local/bin/rotate_backup_keys.sh << 'EOF'
#!/bin/bash
# Script rotazione chiavi crittografia

BACKUP_KEYS_DIR="/root/backup_keys"
DATE=$(date +%Y%m%d)

echo "Rotazione chiavi crittografia..."

# Backup chiavi correnti
mkdir -p "$BACKUP_KEYS_DIR/old_keys_${DATE}"

case $ENCRYPTION_METHOD in
    gpg)
        # Export chiavi correnti
        gpg --export-secret-keys --armor > "$BACKUP_KEYS_DIR/old_keys_${DATE}/gpg_old.asc"
        
        # Genera nuova chiave (manuale - richiede conferma)
        echo "Generazione nuova chiave GPG..."
        echo "Esegui manualmente: gpg --full-generate-key"
        ;;
    age)
        # Backup chiave corrente
        cp /root/.age_private_key.txt "$BACKUP_KEYS_DIR/old_keys_${DATE}/"
        
        # Genera nuova chiave
        age-keygen -o /root/.age_private_key.txt.new
        
        echo "Nuova chiave generata. Per attivarla:"
        echo "  mv /root/.age_private_key.txt.new /root/.age_private_key.txt"
        echo "  age-keygen -y /root/.age_private_key.txt > /root/.age_public_key.txt"
        ;;
esac

echo "✓ Backup chiavi vecchie in: $BACKUP_KEYS_DIR/old_keys_${DATE}"
echo "⚠ Mantieni le chiavi vecchie per decrittare backup esistenti"
EOF

    chmod +x /usr/local/bin/rotate_backup_keys.sh
    echo "✓ Script rotazione chiavi creato: /usr/local/bin/rotate_backup_keys.sh"
}

#===========================================
# CREA SCRIPT DI TEST
#===========================================

create_test_scripts() {
    echo ""
    echo "========================================="
    echo "CREAZIONE SCRIPT DI TEST"
    echo "========================================="
    
    # Script test crittografia
    cat > /usr/local/bin/test_encryption.sh << 'EOF'
#!/bin/bash
# Test sistema crittografia backup

source /etc/backup_encryption.conf 2>/dev/null

echo "Test crittografia/decrittografia..."
TEST_DATA="Test backup data $(date)"
TEST_FILE="/tmp/test_backup_$"

echo "$TEST_DATA" > "$TEST_FILE"

case $ENCRYPTION_METHOD in
    gpg)
        echo "Test GPG..."
        gpg --encrypt --recipient "$GPG_RECIPIENT" --trust-model always -o "${TEST_FILE}.gpg" "$TEST_FILE"
        gpg --decrypt "${TEST_FILE}.gpg" 2>/dev/null | grep -q "$TEST_DATA"
        RESULT=$?
        rm -f "${TEST_FILE}.gpg"
        ;;
    openssl)
        echo "Test OpenSSL..."
        openssl enc -aes-256-cbc -salt -pbkdf2 -in "$TEST_FILE" -out "${TEST_FILE}.enc" -pass file:/root/.backup_passphrase
        openssl enc -d -aes-256-cbc -pbkdf2 -in "${TEST_FILE}.enc" -pass file:/root/.backup_passphrase 2>/dev/null | grep -q "$TEST_DATA"
        RESULT=$?
        rm -f "${TEST_FILE}.enc"
        ;;
    age)
        echo "Test age..."
        age -r "$(cat /root/.age_public_key.txt)" -o "${TEST_FILE}.age" "$TEST_FILE"
        age -d -i /root/.age_private_key.txt "${TEST_FILE}.age" 2>/dev/null | grep -q "$TEST_DATA"
        RESULT=$?
        rm -f "${TEST_FILE}.age"
        ;;
esac

rm -f "$TEST_FILE"

if [ $RESULT -eq 0 ]; then
    echo "✓ Test PASSED: Crittografia/decrittografia funzionante"
    exit 0
else
    echo "✗ Test FAILED: Problema con crittografia"
    exit 1
fi
EOF

    chmod +x /usr/local/bin/test_encryption.sh
    echo "✓ Script test creato: /usr/local/bin/test_encryption.sh"
}

#===========================================
# DOCUMENTAZIONE
#===========================================

create_documentation() {
    echo ""
    echo "========================================="
    echo "CREAZIONE DOCUMENTAZIONE"
    echo "========================================="
    
    cat > /root/BACKUP_ENCRYPTION_README.txt << 'EOF'
========================================
DOCUMENTAZIONE CRITTOGRAFIA BACKUP
========================================

CONFIGURAZIONE
--------------
File configurazione: /etc/backup_encryption.conf
Script backup: /usr/local/bin/postgres_encrypted_backup.sh
Script test: /usr/local/bin/test_encryption.sh

CHIAVI E PASSPHRASE
-------------------
Le chiavi sono salvate in: /root/backup_keys/

GPG:
  - Chiave privata: /root/backup_keys/gpg_private_key.asc
  - Chiave pubblica: /root/backup_keys/gpg_public_key.asc
  - Lista chiavi: gpg --list-keys

OpenSSL:
  - Passphrase: /root/.backup_passphrase
  - Algoritmo: AES-256-CBC con PBKDF2

age:
  - Chiave privata: /root/.age_private_key.txt
  - Chiave pubblica: /root/.age_public_key.txt

COMANDI UTILI
-------------

1. Crittografia manuale file:
   GPG:     gpg --encrypt --recipient backup@hostname -o file.gpg file
   OpenSSL: openssl enc -aes-256-cbc -salt -pbkdf2 -in file -out file.enc -pass file:/root/.backup_passphrase
   age:     age -r $(cat /root/.age_public_key.txt) -o file.age file

2. Decrittografia manuale file:
   GPG:     gpg --decrypt file.gpg > file
   OpenSSL: openssl enc -d -aes-256-cbc -pbkdf2 -in file.enc -pass file:/root/.backup_passphrase > file
   age:     age -d -i /root/.age_private_key.txt file.age > file

3. Verifica integrità:
   GPG:     gpg --list-packets file.gpg
   OpenSSL: openssl enc -d -aes-256-cbc -pbkdf2 -in file.enc -pass file:/root/.backup_passphrase | head -c 1
   age:     age -d -i /root/.age_private_key.txt file.age | head -c 1

4. Test sistema:
   /usr/local/bin/test_encryption.sh

RIPRISTINO BACKUP CRITTOGRAFATO
--------------------------------

1. Con GPG:
   gpg --decrypt backup.dump.gpg | pg_restore -d database_name

2. Con OpenSSL:
   openssl enc -d -aes-256-cbc -pbkdf2 -in backup.dump.enc -pass file:/root/.backup_passphrase | pg_restore -d database_name

3. Con age:
   age -d -i /root/.age_private_key.txt backup.dump.age | pg_restore -d database_name

4. Con split files:
   cat backup_part_*.gpg | gpg -d | pg_restore -d database_name

DISASTER RECOVERY
-----------------

Se perdi le chiavi:
1. Recupera backup chiavi da luogo sicuro
2. GPG: gpg --import gpg_private_key.asc
3. age: copia chiave in /root/.age_private_key.txt
4. OpenSSL: copia passphrase in /root/.backup_passphrase

SICUREZZA
---------

✓ NON condividere mai chiavi private
✓ Conserva backup chiavi in luogo fisico separato
✓ Usa passphrase forti (min 20 caratteri)
✓ Testa periodicamente il ripristino
✓ Ruota chiavi ogni 12 mesi
✓ Monitora accessi ai file di chiavi
✓ Usa permissions corretti (600 per chiavi)

ROTAZIONE CHIAVI
----------------
Script: /usr/local/bin/rotate_backup_keys.sh
Frequenza raccomandata: 12 mesi
Mantieni chiavi vecchie per decrittare backup esistenti

MONITORAGGIO
------------
- Verifica giornaliera backup crittografati
- Alert se crittografia fallisce
- Log: /var/log/postgresql_backup/

CONTATTI EMERGENZA
------------------
Admin: [INSERIRE CONTATTO]
Documento chiavi: [INSERIRE POSIZIONE SICURA]

Data creazione: $(date)
Hostname: $(hostname)
========================================
EOF

    chmod 600 /root/BACKUP_ENCRYPTION_README.txt
    echo "✓ Documentazione creata: /root/BACKUP_ENCRYPTION_README.txt"
}

#===========================================
# BACKUP CHIAVI SU STORAGE ESTERNO
#===========================================

backup_keys_to_external() {
    echo ""
    echo "========================================="
    echo "BACKUP CHIAVI SU STORAGE ESTERNO"
    echo "========================================="
    
    read -p "Vuoi fare backup delle chiavi su storage esterno? (y/n): " do_backup
    
    if [ "$do_backup" != "y" ]; then
        return 0
    fi
    
    read -p "Percorso storage esterno (es. /mnt/usb): " external_path
    
    if [ ! -d "$external_path" ]; then
        echo "ERRORE: Percorso non valido"
        return 1
    fi
    
    BACKUP_PATH="$external_path/backup_keys_$(hostname)_$(date +%Y%m%d)"
    mkdir -p "$BACKUP_PATH"
    
    # Copia chiavi
    cp -r /root/backup_keys/* "$BACKUP_PATH/" 2>/dev/null
    cp /root/.backup_passphrase "$BACKUP_PATH/" 2>/dev/null
    cp /root/.age_private_key.txt "$BACKUP_PATH/" 2>/dev/null
    cp /root/.age_public_key.txt "$BACKUP_PATH/" 2>/dev/null
    cp /root/BACKUP_ENCRYPTION_README.txt "$BACKUP_PATH/"
    
    # Crea file info
    cat > "$BACKUP_PATH/INFO.txt" << EOF
Backup chiavi crittografia
Hostname: $(hostname)
Data: $(date)
Metodo: $(grep ENCRYPTION_METHOD /etc/backup_encryption.conf 2>/dev/null || echo "N/A")

IMPORTANTE:
- Conserva questo storage in luogo sicuro
- Non connettere a sistemi non fidati
- Necessario per recupero in caso di disaster
EOF
    
    # Crea checksum
    cd "$BACKUP_PATH"
    sha256sum * > CHECKSUMS.txt
    cd - > /dev/null
    
    echo "✓ Backup chiavi completato in: $BACKUP_PATH"
    echo ""
    echo "⚠ IMPORTANTE:"
    echo "  1. Disconnetti lo storage esterno"
    echo "  2. Etichetta come 'Backup Keys - $(hostname) - $(date +%Y-%m-%d)'"
    echo "  3. Conserva in cassaforte o luogo sicuro"
    echo "  4. Documenta la posizione"
}

#===========================================
# VERIFICA FINALE
#===========================================

final_verification() {
    echo ""
    echo "========================================="
    echo "VERIFICA FINALE"
    echo "========================================="
    
    local errors=0
    
    # Verifica file configurazione
    if [ -f /etc/backup_encryption.conf ]; then
        echo "✓ File configurazione presente"
    else
        echo "✗ File configurazione mancante"
        errors=$((errors + 1))
    fi
    
    # Verifica chiavi
    source /etc/backup_encryption.conf 2>/dev/null
    
    case $ENCRYPTION_METHOD in
        gpg)
            if gpg --list-keys "$GPG_RECIPIENT" > /dev/null 2>&1; then
                echo "✓ Chiave GPG presente"
            else
                echo "✗ Chiave GPG mancante"
                errors=$((errors + 1))
            fi
            ;;
        openssl)
            if [ -f /root/.backup_passphrase ]; then
                echo "✓ Passphrase OpenSSL presente"
            else
                echo "✗ Passphrase OpenSSL mancante"
                errors=$((errors + 1))
            fi
            ;;
        age)
            if [ -f /root/.age_private_key.txt ] && [ -f /root/.age_public_key.txt ]; then
                echo "✓ Chiavi age presenti"
            else
                echo "✗ Chiavi age mancanti"
                errors=$((errors + 1))
            fi
            ;;
    esac
    
    # Test crittografia
    echo ""
    echo "Esecuzione test crittografia..."
    if /usr/local/bin/test_encryption.sh; then
        echo "✓ Test crittografia passato"
    else
        echo "✗ Test crittografia fallito"
        errors=$((errors + 1))
    fi
    
    echo ""
    if [ $errors -eq 0 ]; then
        echo "✓✓✓ SETUP COMPLETATO CON SUCCESSO ✓✓✓"
        echo ""
        echo "Prossimi passi:"
        echo "1. Leggi documentazione: cat /root/BACKUP_ENCRYPTION_README.txt"
        echo "2. Testa backup crittografato: /usr/local/bin/postgres_encrypted_backup.sh"
        echo "3. Configura cron per backup automatici"
        echo "4. Fai backup delle chiavi in luogo sicuro"
        return 0
    else
        echo "✗✗✗ SETUP COMPLETATO CON $errors ERRORI ✗✗✗"
        echo "Risolvi gli errori prima di procedere"
        return 1
    fi
}

#===========================================
# MAIN
#===========================================

# Verifica root
if [ "$EUID" -ne 0 ]; then
    echo "ERRORE: Questo script deve essere eseguito come root"
    exit 1
fi

# Menu principale
select_encryption_method

# Setup aggiuntivi
setup_key_rotation
create_test_scripts
create_documentation

# Backup chiavi
backup_keys_to_external

# Verifica finale
final_verification

echo ""
echo "========================================="
echo "Setup terminato!"
echo "========================================="

exit 0