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
| 3. AirDrop | Réception d'un fichier | Recevoir un fichier envoyé par l'iPhone : impossible avec la RTL8852BE, fait avec la clé MT7612U | ✅ |
| 3. AirDrop | Découverte | Trouver l'iPhone avec `find` : annonce Bluetooth LE, puis lecture du service dans les trames AWDL | ✅ |
| 3. AirDrop | Envoi d'un fichier | Envoyer un fichier vers l'iPhone avec `send` : texte et photo reçus, ouverts dans Fichiers | ✅ |
| 4. Clé MT7612U | Capacités | Vérifier la puce et le mode moniteur actif (`lsusb`, `iw list`) : MT7612U reconnue par `mt76x2u`, mode moniteur actif présent, canaux 6, 44 et 149 disponibles | ✅ |
| 4. Clé MT7612U | Contournements | Refaire l'injection et la réception sur 6, 44 et 149 : injection et réception sans contournement en mode simple, mode actif seulement avec une interface d'aide | ✅ |
| 4. Clé MT7612U | Réception | Relancer `receive` avec `IFACE=<interface de la clé>` : les réponses du PC passent, photos reçues après décodage du format `x-dvzip` | ✅ |
| 4. Clé MT7612U | Débit | Mesurer le débit sur plusieurs envois : environ 1 à 1,3 Mo/s, 39 Mo en 20 photos à 1,19 Mo/s | ✅ |
| 5. Confort | Réannonce | Réannoncer le service mDNS à chaque nouvelle recherche de l'iPhone, pour éviter de relancer le script : signal `SIGUSR1` à OpenDrop sur `add peer` ou `changed channel sequence` | ✅ |
| 5. Confort | HEIC | Déclarer le HEIC à l'iPhone pour recevoir les photos d'origine | ✅ |
| 5. Confort | Vidéos et Live Photos | Recevoir les vidéos HEVC et les Live Photos sans conversion (reporté) | ⬜ |
| 5. Confort | Noms de fichiers en double | Ne pas écraser un fichier déjà reçu sous le même nom : suffixe ` (2)` | ✅ |
| 5. Confort | Extraction sûre | Refuser les chemins qui sortent du dossier de réception, ignorer les liens symboliques | ✅ |
| 5. Confort | Point d'accès éphémère | Le retirer du chemin de la clé : lancé seulement avec un pilote `rtw89` | ✅ |
| 5. Confort | Mode moniteur actif | Comprendre pourquoi l'iPhone n'envoie rien dans ce mode | ⬜ |
| 5. Confort | Type de fichier à l'envoi | Déclarer le bon type (`public.heic`, `public.jpeg`...) pour que les photos envoyées arrivent dans Photos | ⬜ |
