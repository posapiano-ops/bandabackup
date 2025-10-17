# Sincronizza backup su server remoto
rsync -avz --delete \
    -e "ssh -i /root/.ssh/backup_key" \
    /backup/ \
    user@remote-server:/backup/myapp/