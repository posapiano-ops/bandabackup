# Decomprimi e ripristina
gunzip < backup.sql.gz | mysql -u username -p database_name

# Estrai backup
tar -xzf app_backup.tar.gz -C /var/www/html/

# Ripristina permessi
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html