# Ripristino rapido

## database MySQL
```bash
gunzip < backup.sql.gz | mysql -u username -p database_name
```
## File PHP
```bash
# Estrai backup
tar -xzf app_backup.tar.gz -C /var/www/html/

# Ripristina permessi (debian/ubuntu)
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
```
