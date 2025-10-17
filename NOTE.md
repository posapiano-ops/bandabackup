# Opzioni di Backup MySQL
### Per database piccoli/medi:
* `--single-transaction`: backup consistente senza bloccare le tabelle (InnoDB)
* `--quick`: per database grandi, non carica tutto in memoria

### Per database grandi:

* Considera **Percona XtraBackup** per backup incrementali
* Backup fisici più veloci del dump logico

### Backup incrementali mysql
https://medium.com/@masterix/backup-mysql-in-ambienti-linux-869cf2b23004



# Checklist Finale
✅ Backup database automatizzato giornaliero
✅ Backup file applicazione
✅ Backup configurazioni separate
✅ Copia remota/cloud
✅ Test di ripristino mensile
✅ Monitoraggio e alerting
✅ Documentazione procedura ripristino
✅ Crittografia backup sensibili