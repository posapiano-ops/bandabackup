<?php
// backup_manager.php

class BackupManager {
    private $dbHost = 'localhost';
    private $dbUser = 'username';
    private $dbPass = 'password';
    private $dbName = 'database';
    private $backupDir = '/backups/';
    
    public function backupDatabase() {
        $filename = $this->backupDir . 'db_' . date('Ymd_His') . '.sql.gz';
        
        $command = sprintf(
            'mysqldump -h%s -u%s -p%s %s | gzip > %s',
            escapeshellarg($this->dbHost),
            escapeshellarg($this->dbUser),
            escapeshellarg($this->dbPass),
            escapeshellarg($this->dbName),
            escapeshellarg($filename)
        );
        
        exec($command, $output, $return);
        
        return $return === 0 ? $filename : false;
    }
    
    public function backupFiles($sourceDir, $excludeDirs = []) {
        $filename = $this->backupDir . 'files_' . date('Ymd_His') . '.tar.gz';
        
        $excludeParams = '';
        foreach ($excludeDirs as $dir) {
            $excludeParams .= " --exclude='" . $dir . "'";
        }
        
        $command = "tar -czf {$filename} {$excludeParams} -C {$sourceDir} .";
        exec($command, $output, $return);
        
        return $return === 0 ? $filename : false;
    }
    
    public function cleanOldBackups($days = 30) {
        $files = glob($this->backupDir . '*');
        $now = time();
        
        foreach ($files as $file) {
            if (is_file($file)) {
                if ($now - filemtime($file) >= 60 * 60 * 24 * $days) {
                    unlink($file);
                }
            }
        }
    }
}

// Utilizzo
$backup = new BackupManager();
$backup->backupDatabase();
$backup->backupFiles('/var/www/html', ['vendor', 'cache', 'node_modules']);
$backup->cleanOldBackups(30);