# Opzioni di Backup MySQL
### Per database piccoli/medi:
* `--single-transaction`: backup consistente senza bloccare le tabelle (InnoDB)
* `--quick`: per database grandi, non carica tutto in memoria

### Per database grandi:

* Considera **Percona XtraBackup** per backup incrementali
* Backup fisici più veloci del dump logico

### Backup incrementali mysql
https://medium.com/@masterix/backup-mysql-in-ambienti-linux-869cf2b23004

pt-show-grants from Percona Toolkit
```
MYSQL_CONN="-uroot -ppassword"
pt-show-grants ${MYSQL_CONN} &gt;mysqlusegrants.sql
```

```
MYSQL_CONN="-uroot -ppassword"
mysql ${MYSQL_CONN} --skip-column-names -A -e"SELECT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') FROM mysql.user WHERE user<>''" | mysql ${MYSQL_CONN} --skip-column-names -A | sed 's/$/;/g' > MySQLUserGrants.sql
```

Postgres users
```
pg_dumpall --globals-only --file=all_roles_and_user.sql
```