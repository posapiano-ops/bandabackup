# Opzioni di Backup MySQL
### Per database piccoli/medi:
* `--single-transaction`: backup consistente senza bloccare le tabelle (InnoDB)
* `--quick`: per database grandi, non carica tutto in memoria

### Per database grandi:

* Considera **Percona XtraBackup** per backup incrementali
* Backup fisici più veloci del dump logico

### Backup incrementali mysql
https://medium.com/@masterix/backup-mysql-in-ambienti-linux-869cf2b23004

