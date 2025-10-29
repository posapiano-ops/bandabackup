# ========================================
# GUIDA RAPIDA: BACKUP CRITTOGRAFATI
# ========================================

# STEP 1: Setup iniziale (una sola volta)
# ----------------------------------------

# Esegui setup automatico
chmod +x /usr/local/bin/setup_encryption.sh
/usr/local/bin/setup_encryption.sh

# Seleziona metodo (raccomandazioni):
# - GPG: Ambiente enterprise, multiple chiavi, massima sicurezza
# - OpenSSL: Semplice, basato su passphrase, buona sicurezza
# - age: Moderno, semplice, ottimo per automazione

# STEP 2: Configurazione backup
# ------------------------------

# Copia script backup crittografato
chmod +x /usr/local/bin/postgres_encrypted_backup.sh

# Modifica configurazione nel file
vim /usr/local/bin/postgres_encrypted_backup.sh
# Aggiorna: PGDATABASE, GPG_RECIPIENT, ADMIN_EMAIL

# Test manuale
/usr/local/bin/postgres_encrypted_backup.sh

# STEP 3: Automazione con cron
# -----------------------------

crontab -e
# Aggiungi:
0 2 * * * /usr/local/bin/postgres_encrypted_backup.sh >> /var/log/encrypted_backup_cron.log 2>&1

# STEP 4: Backup chiavi (CRITICO!)
# ---------------------------------

# Backup su USB/storage esterno
mount /dev/sdb1 /mnt/usb
cp -r /root/backup_keys /mnt/usb/backup_keys_$(hostname)_$(date +%Y%m%d)
umount /mnt/usb

# Conserva in luogo sicuro fisico (cassaforte)

# STEP 5: Test ripristino
# -----------------------

# Test in ambiente di sviluppo
/usr/local/bin/restore_encrypted_backup.sh

# Seleziona opzione 3 (Solo verifica)

# ========================================
# COMANDI RAPIDI
# ========================================

# Crittografa file manualmente
gpg --encrypt --recipient backup@hostname -o file.gpg file

# Decrittografa e ripristina
gpg --decrypt backup.dump.gpg | pg_restore -d dbname

# Verifica backup crittografato
/usr/local/bin/restore_encrypted_backup.sh
# Seleziona opzione 5

# Lista backup disponibili
find /backup/postgresql/encrypted -type f -name "*.gpg" -printf '%T+ %p\n' | sort

# Test sistema crittografia
/usr/local/bin/test_encryption.sh

# ========================================
# DISASTER RECOVERY
# ========================================

# 1. Recupera chiavi da backup fisico
# 2. Importa chiavi:

# GPG:
gpg --import /path/to/gpg_private_key.asc

# OpenSSL:
cp /path/to/passphrase /root/.backup_passphrase
chmod 400 /root/.backup_passphrase

# age:
cp /path/to/age_private_key.txt /root/.age_private_key.txt
chmod 400 /root/.age_private_key.txt

# 3. Esegui ripristino
/usr/local/bin/restore_encrypted_backup.sh

# ========================================
# SICUREZZA
# ========================================

# Permessi corretti
chmod 400 /root/.backup_passphrase
chmod 400 /root/.age_private_key.txt
chmod 600 /root/backup_keys/*
chmod 600 /etc/backup_encryption.conf

# Audit accessi chiavi
auditctl -w /root/backup_keys -p rwxa -k backup_keys_access
auditctl -w /root/.backup_passphrase -p rwxa -k passphrase_access

# Monitoring
tail -f /var/log/postgresql_backup/encrypted_backup_*.log

# ========================================
# BEST PRACTICES
# ========================================

✓ Testa ripristino mensile
✓ Backup chiavi in 2+ luoghi fisici separati
✓ Documenta posizione chiavi
✓ Ruota chiavi ogni 12 mesi
✓ Mantieni chiavi vecchie per backup esistenti
✓ Usa passphrase forti (min 20 caratteri)
✓ Non memorizzare chiavi su server backup
✓ Monitora accessi ai file di chiavi
✓ Verifica integrità backup settimanalmente
✓ Crittografa anche backup remoti/cloud
```

## 5. Tabella Comparativa Metodi Crittografia

| Caratteristica | GPG | OpenSSL | age |
|---------------|-----|---------|-----|
| **Sicurezza** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Facilità uso** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Setup** | Complesso | Semplice | Molto semplice |
| **Gestione chiavi** | Avanzata | Base | Semplice |
| **Multiple destinatari** | ✅ | ❌ | ✅ |
| **Firma digitale** | ✅ | ❌ | ❌ |
| **Standard industria** | ✅ | ✅ | Emergente |
| **Performance** | Media | Alta | Molto alta |
| **Dimensione overhead** | ~5% | ~3% | ~1% |
| **Automazione** | Medio | Facile | Molto facile |

## 6. Checklist Finale
```
□ Sistema crittografia configurato
□ Chiavi generate e testate
□ Backup chiavi fatto in luogo sicuro
□ Passphrase documentata separatamente
□ Script backup crittografato testato
□ Cron job configurato
□ Script ripristino testato
□ Documentazione scritta e accessibile
□ Team informato sulla procedura
□ Piano disaster recovery aggiornato
□ Monitoring configurato
□ Alert configurati per errori crittografia
□ Test ripristino eseguito con successo
□ Permessi file verificati (600/400)
□ Audit log configurato
□ Procedura rotazione chiavi pianificata