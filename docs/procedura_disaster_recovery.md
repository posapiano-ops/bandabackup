# PROCEDURA DISASTER RECOVERY

## Scenario 1: Perdita Database
1. Accedere al server come root
2. Eseguire: /usr/local/bin/restore_system.sh
3. Selezionare opzione 2 (Solo PostgreSQL)
4. Seguire wizard interattivo
5. Verificare applicazioni

## Scenario 2: Perdita WildFly
1. Accedere al server come root
2. Eseguire: /usr/local/bin/restore_system.sh
3. Selezionare opzione 4 (Solo WildFly)
4. Verificare deployments
5. Test applicazioni

## Scenario 3: Disaster Completo
1. Installare OS su nuovo server
2. Installare PostgreSQL e WildFly
3. Recuperare backup da remoto/cloud
4. Eseguire restore_system.sh opzione 1
5. Verificare tutti i servizi

## Scenario 4: Point-in-Time Recovery
1. Identificare timestamp target
2. Eseguire restore_system.sh opzione 3
3. Inserire timestamp richiesto
4. Attendere applicazione WAL
5. Verificare consistenza dati

## Tempi di Recovery Stimati
- Database piccolo (<10GB): 15-30 min
- Database medio (10-100GB): 1-3 ore
- Database grande (>100GB): 3-8 ore
- WildFly: 10-20 minuti