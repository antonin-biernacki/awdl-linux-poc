# Feuille de route

## Légende

⬜ à faire, 🟡 en cours, ✅ fait.

| Phase | Étape | Description | État |
|---|---|---|---|
| 1. Carte Wi-Fi | Injection | Injecter des trames avec la RTL8852BE (fonctionne en 5 GHz) | ✅ |
| 1. Carte Wi-Fi | Réception AWDL | Recevoir le trafic AWDL des appareils Apple (avec le contournement du point d'accès éphémère) | ✅ |
| 2. AWDL | Interface `awdl0` | Faire créer l'interface `awdl0` par OWL | ✅ |
| 2. AWDL | Synchronisation | Synchroniser OWL avec un iPhone | ✅ |
| 3. AirDrop | Script | Écrire `scripts/airdrop-poc.sh` avec les modes `find`, `receive` et `send` | ✅ |
| 3. AirDrop | Connexion de l'iPhone | Obtenir des connexions TLS de l'iPhone vers le port 8771 en `receive` | ✅ |
| 3. AirDrop | Réception d'un fichier | Recevoir un fichier envoyé par l'iPhone : les réponses du PC se perdent | 🟡 |
| 3. AirDrop | Découverte | Trouver l'iPhone avec `find` : bloqué, l'iPhone attend une annonce Bluetooth LE qu'OpenDrop ne sait pas faire | ⬜ |
| 3. AirDrop | Envoi d'un fichier | Envoyer un fichier vers l'iPhone avec `send` : bloqué comme `find` | ⬜ |
| 4. Clé MT7612U | Capacités | Vérifier la puce et le mode moniteur actif (`lsusb`, `iw list`) : MT7612U reconnue par `mt76x2u`, mode moniteur actif présent, canaux 6, 44 et 149 disponibles | ✅ |
| 4. Clé MT7612U | Contournements | Refaire l'injection et la réception sur 6, 44 et 149 pour savoir si les contournements restent nécessaires | ⬜ |
| 4. Clé MT7612U | Réception | Relancer `receive` avec `IFACE=<interface de la clé>` et comparer avec l'essai 13 | ⬜ |
| 4. Clé MT7612U | Débit | Recevoir un premier fichier et mesurer le débit | ⬜ |
