# Configurazione per S3, Google Drive, ecc.
rclone sync /backup/ remote:mybucket/backup/ \
    --transfers 4 \
    --checkers 8 \
    --contimeout 60s \
    --timeout 300s \
    --retries 3