# Résultats de recherche

## Sommaire

- [Résumé](#résumé)
- [Méthode](#méthode)
- [Résultats](#résultats)
  - [R1](#r1)
  - [R2](#r2)
  - [R3](#r3)
  - [R4](#r4)
  - [R5](#r5)
  - [R6](#r6)
  - [R7](#r7)
  - [R8](#r8)
  - [R9](#r9)
  - [R10](#r10)
  - [R11](#r11)
  - [R12](#r12)
  - [R13](#r13)
- [Essais](#essais)
- [Pistes écartées](#pistes-écartées)
- [Questions ouvertes](#questions-ouvertes)

## Résumé

Sur une RTL8852BE, la couche AWDL fonctionne avec deux contournements : pas de mode moniteur actif, et une réception limitée au dernier canal utilisé par le firmware. L'iPhone voit alors le PC et ouvre des connexions TLS, mais les réponses du PC se perdent.

Avec une clé USB MT7612U en mode moniteur simple, les réponses du PC arrivent et le PC reçoit des photos de l'iPhone. La carte était donc bien en cause. Le mode moniteur actif de la clé empêche au contraire l'iPhone d'envoyer des données. Les iOS récents envoient les fichiers au format `x-dvzip`, une suite de blocs zlib autour de l'archive cpio habituelle. Photos et vidéos arrivent dans leur format d'origine si le PC annonce les capacités média d'un iPhone. Les Live Photos arrivent en image fixe.

Dans l'autre sens, une annonce Bluetooth LE réveille l'appareil Apple, qui annonce son serveur AirDrop dans ses trames AWDL. Avec un envoi au format d'iOS, des données en 802.11n et une connexion sans certificat client, le PC envoie des fichiers à un iPhone et à un iPad, à environ 1,2 Mo/s.

## Méthode

Matériel et logiciels : voir [Matériel](README.md#matériel) dans le README.

Le script `scripts/airdrop-poc.sh` :

1. avec une carte `rtw89`, lance un point d'accès éphémère sur le canal 149, puis le coupe (contournement de [R2](#r2)). Avec un autre pilote, comme `mt76x2u`, cette étape est sautée ;
2. passe la carte en mode moniteur simple sur ce canal (contournement de [R1](#r1)) ;
3. démarre OWL en arrière-plan et attend que `awdl0` ait une adresse IPv6 ;
4. lance OpenDrop sur `awdl0`, avec les droits de l'utilisateur ;
5. en `receive`, demande à OpenDrop de réannoncer son service quand l'iPhone commence une nouvelle recherche ([R9](#r9)). En `find` et `send`, lit dans les trames AWDL les récepteurs annoncés et émet l'annonce Bluetooth LE d'AirDrop ([R11](#r11)) ;
6. à la sortie (fin normale, erreur ou Ctrl+C), arrête OWL, supprime le point d'accès, remet la carte en Wi-Fi normal et copie les journaux et captures du run dans `out/runs/<date>-<mode>/` (`out/latest` pointe vers le dernier).

Observation :

- journaux d'OWL (`out/owl.log`) et d'OpenDrop (`out/opendrop.log`) ;
- avec `CAPTURE=1`, captures de `awdl0` (`out/awdl0.pcap`) et des trames Wi-Fi brutes (`out/wlan.pcap`), résumées par `scripts/diagnostics/summarize-run.sh` ;
- les trames AWDL sont repérées avec le dissecteur `awdl` de `tshark` ;
- les scripts de `scripts/diagnostics/` ont servi aux essais 1 à 8 (injection, scan passif, réception canal par canal, astuce du point d'accès, OWL au premier plan) ;
- avec la clé USB, `IFACE` désigne l'interface de la clé : le script ne touche qu'à elle et la carte intégrée reste connectée. `ACTIVE_MONITOR=1` remplace les étapes 1 et 2 par le montage de [R7](#r7) ;
- `scripts/diagnostics/adapter-test.sh` teste une carte canal par canal : fréquence réellement écoutée, trames AWDL reçues, injection (essais 15 et 17).

Remarques :

- les appareils Apple utilisent des adresses MAC aléatoires et des noms d'hôte en UUID, donc je ne peux pas toujours dire lequel est mon iPhone ;
- l'iPhone suivait la séquence de canaux 48, 149 et 6. OWL reste sur le 149, ce qui suffit pour se synchroniser.

## Résultats

### R1

**La RTL8852BE injecte des trames en 5 GHz, mais n'a pas de mode moniteur actif.**

- Preuves : `aireplay-ng --test` sur le canal 157 donne "Injection is working!" avec 6 points d'accès (essai 2). OWL avec ses réglages par défaut échoue avec `Could not put device in monitor mode` (essai 3).
- Contournement : passer soi-même la carte en mode moniteur simple, puis lancer OWL avec `-N` pour qu'il ne touche pas à sa configuration. Contrepartie : sans ACK, l'émetteur répète ses trames jusqu'à 7 fois et le débit sera dégradé.
- Date : inconnue
- Produit par : `scripts/diagnostics/injection-test-2.sh`, `scripts/diagnostics/owl-test.sh`

```bash
ip link set wlp2s0 down
iw dev wlp2s0 set type monitor
ip link set wlp2s0 up
owl -i wlp2s0 -c 149 -N
```

### R2

**En mode moniteur, la carte ne reçoit que sur le dernier canal utilisé par le firmware.**

- Preuves : en scan passif, le canal 157 reçoit environ 900 trames, les canaux 6, 44 et 149 entre 0 et 1 (essai 5). Seul le 157 reçoit, alors que des points d'accès émettent sur 6, 48 et 112 (essai 6). Après un point d'accès éphémère, la carte reçoit sur 149, 44 et 6, et les trames AWDL sont décodées (essai 7).
- Contournement : faire d'abord travailler le firmware sur le canal voulu avec un point d'accès éphémère. Ce comportement n'est pas documenté : une mise à jour du noyau ou du firmware peut le corriger, ou casser le contournement.
- Date : inconnue
- Produit par : `scripts/diagnostics/awdl-scan.sh`, `scripts/diagnostics/channel-test.sh`, `scripts/diagnostics/hotspot-trick.sh`

```bash
nmcli device wifi hotspot ifname wlp2s0 band a channel 149 ssid poc-tmp password <mot-de-passe>
nmcli connection down Hotspot
nmcli device set wlp2s0 managed no
# puis le contournement de R1, et :
iw dev wlp2s0 set channel 149
```

### R3

**Avec les deux contournements, OWL se synchronise avec l'iPhone, qui voit le PC et ouvre des connexions TLS.**

- Preuves : OWL affiche `add peer` et se synchronise (essai 8). En `receive`, l'iPhone voit "poc", ouvre une connexion TLS vers le port 8771 et envoie `POST /Discover` (essai 11). Sans `-f`, la synchronisation est stable et l'iPhone ouvre 7 connexions TLS (essai 13).
- Date : inconnue
- Produit par : `sudo bash scripts/airdrop-poc.sh receive`

### R4

**Les réponses TLS du PC n'arrivent pas à l'iPhone.**

- Preuves : pendant l'essai 13, l'iPhone reçoit nos petits paquets (SYN-ACK), mais nos segments de 1043 et 1378 octets (la réponse TLS) sont retransmis pendant 5 secondes sans être acquittés. L'essai 11 est le seul où la réponse TLS du PC est passée. Découper la réponse en segments de 488 octets ne change rien (essai 14).
- Captures : sur 452 trames de données envoyées par l'iPhone lors d'un essai, 388 sont des retransmissions, car la carte n'acquitte rien. Aucune des 235 trames du PC vers l'iPhone n'est retransmise au niveau Wi-Fi : une trame qui part quand l'iPhone écoute un autre canal est perdue.
- L'iPhone envoie des accusés de réception Wi-Fi à certaines de nos trames, mais je ne peux pas les associer de façon fiable aux trames émises : la capture horodate nos trames quand elles sont confiées à la carte, pas quand elles partent.
- Avec la clé MT7612U, le problème disparaît ([R6](#r6)) : il venait de la RTL8852BE ou de son pilote.
- Date : inconnue
- Produit par : `sudo CAPTURE=1 bash scripts/airdrop-poc.sh receive`, puis `bash scripts/diagnostics/summarize-run.sh`

### R5

**L'iPhone n'ouvre son serveur AirDrop qu'après une annonce Bluetooth LE, et il annonce ce serveur dans ses trames AWDL, pas en mDNS.**

- Preuves : avec la feuille de partage ouverte sur l'iPhone, `find` ne trouve aucun appareil (essai 9). L'iPhone n'ouvre son serveur AirDrop qu'après une annonce Bluetooth LE, qu'OpenDrop ne sait pas faire. C'est une limite connue d'OpenDrop.
- Avec l'annonce Bluetooth émise par le script, l'iPhone allume AWDL et OWL se synchronise. L'iPhone ne répond pas aux requêtes mDNS sur `awdl0`, mais il annonce `_airdrop._tcp` dans ses trames AWDL : TLV "Service Response" avec PTR, SRV (port 8770) et TXT (`flags`). OWL ignore ces TLV (essai 29).
- Contournement : le script lit ces TLV avec `tshark` et les passe à OpenDrop, qui trouve alors l'iPhone ([R11](#r11)).
- Date : inconnue (essai 9), 2026-11-25 (essai 29)
- Produit par : `sudo IFACE=wlp4s0f4u1 CAPTURE=1 bash scripts/airdrop-poc.sh find`

### R6

**Avec une clé USB MT7612U en mode moniteur simple, le PC reçoit des photos de l'iPhone.**

- Preuves : en mode moniteur simple, la clé écoute le canal demandé sans point d'accès éphémère (essai 16). Elle reçoit les trames AWDL de l'iPhone sur 149 et 6, et injecte sur 6, 44 et 149 (essais 17 et 18). En `receive`, l'iPhone voit "poc" et acquitte environ 3,3 Ko de réponse TLS par connexion, contre 0 avec la RTL8852BE (essai 20). Une photo de 3,59 Mo est reçue et extraite, l'iPhone affiche "Envoyé" (essai 22).
- Débit : 0,93 Mo/s pour cette photo, puis 0,97 à 1,30 Mo/s par envoi dans les essais 24 à 28, et 39,08 Mo (20 photos d'un coup) à 1,19 Mo/s (essai 26). Mesures d'OpenDrop.
- Le script ne touche qu'à la clé : la carte intégrée reste connectée (vérifié après les essais 15 et 17).
- Dans cet essai, l'iPhone convertit ses photos en JPEG, car OpenDrop ne déclare pas le format HEIC dans sa réponse (`ReceiverMediaCapabilities`). Voir [R10](#r10).
- Sans point d'accès éphémère, la clé fonctionne aussi (essai 26) : le script ne le lance plus qu'avec un pilote `rtw89`.
- Date : 2026-11-25
- Produit par : `sudo IFACE=wlp4s0f4u1 CAPTURE=1 bash scripts/airdrop-poc.sh receive`

### R7

**En mode moniteur actif, la MT7612U ne change de canal qu'avec une interface d'aide, et l'iPhone ne lui envoie aucune donnée.**

- Preuves : seule en mode moniteur actif, la clé reste sur 2412 MHz (canal 1), quel que soit le canal demandé, et `iw` ne signale aucune erreur (essais 15 et 16). Si une interface moniteur simple est ouverte avant l'interface active, le canal suit (essai 17). OWL se synchronise alors avec l'iPhone, mais l'iPhone n'envoie aucune trame de données en 160 s et n'affiche pas "poc" (essai 19).
- Explication probable : le noyau ne règle le canal d'une interface moniteur qu'à travers une interface moniteur "virtuelle", qu'il ne crée que si une interface moniteur simple s'ouvre en premier. Je ne sais pas encore pourquoi l'iPhone n'envoie rien dans ce mode.
- Date : 2026-11-25
- Produit par : `scripts/diagnostics/adapter-test.sh`, `ACTIVE_MONITOR=1` dans `scripts/airdrop-poc.sh`

```bash
iw phy phy2 interface add pocmon0 type monitor
ip link set pocmon0 up
iw dev wlp4s0f4u1 set type monitor
iw dev wlp4s0f4u1 set monitor active otherbss control
ip link set wlp4s0f4u1 up
iw dev wlp4s0f4u1 set channel 149
```

### R8

**Les iOS récents envoient les fichiers au format `x-dvzip` : une suite de blocs zlib autour d'une archive cpio.**

- Preuves : l'iPhone envoie `/Upload` avec `Content-Type: application/x-dvzip`, qu'OpenDrop 0.13.0 refuse (essai 20). La copie brute de 3,76 Mo (essai 21) se lit ainsi : chaque bloc commence par sa longueur sur 4 octets (big-endian). Si le bit de poids fort est à 1, le bloc est stocké tel quel, sinon c'est un flux zlib de 128 Kio une fois décompressé. Les blocs mis bout à bout forment une archive cpio (format odc), qui contient la photo intacte.
- Correctif : `patches/opendrop-dvzip.patch` décode ce format avant l'extraction. Si l'extraction échoue, la copie brute est gardée dans `out/received/` pour l'étudier.
- L'archive contient aussi, pour chaque fichier, un fichier AppleDouble `._nom` avec des métadonnées macOS (essai 23). Le correctif les ignore à l'extraction.
- Avec plusieurs fichiers, chacun est rangé dans un dossier temporaire `NSIRD_AirDrop_xxxxxx/` (essai 26). Le correctif retire ce dossier. Une Live Photo arrive dans un dossier `nom.pvt/`, gardé tel quel.
- Le correctif renomme un fichier déjà présent en `nom (2).ext`, `nom (3).ext`... au lieu de l'écraser (essai 26).
- En `receive`, n'importe quel appareil à portée peut envoyer une archive. L'extraction refuse donc les chemins absolus et `..`, et ignore les liens symboliques. Vérifié avec des archives piégées : rien n'est écrit hors du dossier de réception.
- Date : 2026-11-25
- Produit par : `patches/opendrop-dvzip.patch`, appliqué par `scripts/setup-opendrop.sh`

```text
[longueur 4 octets][bloc][longueur 4 octets][bloc]...
bit de poids fort de la longueur = 1 : bloc stocké sans compression
bit de poids fort de la longueur = 0 : bloc zlib
```

### R9

**À chaque nouvelle recherche AirDrop, l'iPhone ne revoit le PC que si celui-ci réannonce son service mDNS.**

- Preuves : sans réannonce, l'iPhone revenu sur AWDL n'envoie aucune requête et ne revoit pas "poc" (essai 22). Avec une réannonce sur `add peer`, "poc" réapparaît 6 s après la réouverture et un deuxième fichier est reçu (essai 23). Mais si l'iPhone rouvre sa feuille sans quitter AWDL, OWL n'affiche pas `add peer` et "poc" disparaît (essai 27). Avec une réannonce aussi sur `changed channel sequence`, quatre envois de suite passent sans relancer le script (essai 28).
- Mécanisme : `patches/opendrop-reannounce.patch` fait réannoncer le service par OpenDrop quand il reçoit `SIGUSR1`. `scripts/airdrop-poc.sh` envoie ce signal quand le journal d'OWL affiche `add peer` (l'iPhone revient sur AWDL) ou `changed channel sequence` (il commence une nouvelle recherche), au plus une fois toutes les 3 s.
- Le signal ne part qu'après la ligne `Service announced` d'OpenDrop, et OpenDrop l'ignore jusque-là. Pendant l'enregistrement, zeroconf vérifie que le nom est libre : une réannonce à ce moment ressemble à un autre appareil qui porte le même nom, et OpenDrop s'arrête (`NonUniqueNameException`, essai 27).
- Date : 2026-11-25
- Produit par : `sudo IFACE=wlp4s0f4u1 CAPTURE=1 bash scripts/airdrop-poc.sh receive`

### R10

**En annonçant les mêmes capacités média qu'un iPhone sous iOS 26, le PC reçoit les photos (HEIC) et les vidéos (HEVC, HDR) dans leur format d'origine. Les Live Photos arrivent sans leur vidéo.**

- Preuves : avec les capacités relevées sur macOS 10.13.3 par OpenDrop (`Version` 1, `VTMaxPlaybackLevel`), les photos arrivent en HEIC, mais une vidéo HEVC arrive en H.264, 1080p, 30 images/s. Sa date `creation_time` est celle de l'envoi, alors que `com.apple.quicktime.creationdate` est celle du tournage : l'iPhone la réencode pendant l'envoi (essai 24).
- Capacités d'iOS 26 : un iPhone récepteur les donne dans sa réponse à `/Discover`, qu'OpenDrop enregistre avec `-d` dans `~/.opendrop/debug/send_discover_response.plist` (essai 36). Différences principales : `Version` 3, `VTMaxDecodeLevel` 180 au lieu de `VTMaxPlaybackLevel`, Dolby Vision (`VTDoViSupportedProfiles` 05 et 08), `VTIsHDRAllowedOnDevice`, conteneurs HEIF `avif` et `heics`, `SupportsAdjustmentBaseResources`, `AssetBundleFormatVersion`.
- Avec ces capacités recopiées à l'identique, la vidéo arrive en HEVC (`hvc1`, HDR HLG), 3,98 Mo au lieu de 6,9 Mo en H.264, avec `creation_time` à l'heure du tournage (essai 37).
- Live Photos : l'iPhone ne propose que l'image fixe dès sa demande d'envoi (un seul fichier HEIC, `ShouldConvertMediaFormats` à vrai), pastille "Live" activée. Il décide donc avant `/Ask`, d'après la réponse à `/Discover`. Ni les capacités d'iOS 26 ni un modèle de Mac (`-m`) n'y changent rien (essais 35, 37 et 38).
- Débit : 0,95 à 1,12 Mo/s par fichier, mesuré par OpenDrop (essais 24 à 38).
- Date : 2026-11-25
- Produit par : `patches/opendrop-media-capabilities.patch`, puis `sudo IFACE=wlp4s0f4u1 CAPTURE=1 OPENDROP_ARGS="-d" bash scripts/airdrop-poc.sh receive` (`-d` enregistre les requêtes de l'iPhone dans `~/.opendrop/debug/`)

### R11

**Avec une annonce Bluetooth LE, la lecture des trames AWDL et un envoi au format d'iOS, le PC envoie des fichiers à l'iPhone.**

- Preuves : `find` affiche l'iPhone avec son nom (essai 31). `send` envoie un fichier texte de 89 octets et une photo HEIC de 2,94 Mo. OpenDrop affiche `Uploading has been successful`, et l'iPhone ouvre les fichiers dans l'app Fichiers (essai 33).
- Débit : 2,94 Mo en 4,9 s après l'acceptation, soit 0,60 Mo/s.
- Annonce Bluetooth : données constructeur Apple (`0x004c`), type AirDrop `0x05`, 18 octets dont quatre empreintes tronquées de l'identité de l'expéditeur. Avec des empreintes nulles, un iPhone en "Tout le monde" répond. Le script l'émet avec `btmgmt add-adv`, puis remet le Bluetooth dans son état de départ.
- Découverte : le script écrit chaque récepteur annoncé dans les trames AWDL dans `out/awdl-peers.txt` (adresse MAC, port, instance, flags). `patches/opendrop-awdl-peers.patch` ajoute à OpenDrop l'option `--peers-file`, qui lit ce fichier et déduit l'adresse IPv6 lien-local de l'adresse MAC (EUI-64).
- Compatibilité : OpenDrop 0.13.0 ne tourne plus avec Python 3.12 et plus (`HTTPSConnection` sans `key_file` ni `cert_file`), avec libarchive-c 5 (constructeur de `ArchiveEntry` changé) ni avec Pillow 10 (`Image.ANTIALIAS` supprimé, utilisé pour la vignette d'une image). `patches/opendrop-compat.patch` corrige les trois (essais 30, 31 et 34).
- Envoi : avec l'envoi d'origine d'OpenDrop, l'iPhone accepte puis garde une barre de progression figée, sans répondre à `/Upload` (essai 32). `patches/opendrop-send-ios.patch` envoie comme iOS : archive en `x-dvzip`, `FileSize` pour chaque fichier et `TransferID` dans `/Ask`, en-têtes `TotalBytes` et `TransferID` dans `/Upload` (essai 33).
- Type de fichier : OpenDrop devinait le type avec `fleep`, qui ne reconnaît ni le HEIC ni le texte. Il déclarait alors `public.content`, et l'iPhone rangeait tout dans Fichiers (essai 33). Le correctif déclare le type d'après l'extension (`public.heic`, `public.jpeg`, `public.png`, `public.plain-text`...), `fleep` restant en secours : une photo HEIC et une photo JPEG s'ouvrent dans Photos (essai 34). Le HEIC part sans vignette, ce qui ne gêne pas.
- Date : 2026-11-25
- Produit par : `sudo IFACE=wlp4s0f4u1 bash scripts/airdrop-poc.sh send FICHIER`

### R12

**OWL envoyait toutes ses trames à 12 Mbit/s. En envoyant les données en 802.11n, l'envoi vers l'iPhone passe de 0,60 à 1,20 Mo/s.**

- Cause : OWL écrit dans l'en-tête radiotap de chaque trame émise un débit fixe de 12 Mbit/s (`src/tx.c`, avec un commentaire "TODO" sur le sujet). Dans l'autre sens, l'iPhone envoie à 54 à 121 Mbit/s en 802.11n.
- Correctif : `patches/owl-tx-mcs.patch`. Les trames de données unicast portent un champ radiotap MCS (802.11n, un flux, 20 MHz, intervalle de garde long), avec l'index lu dans la variable d'environnement `OWL_TX_MCS` (0 à 7). Les trames AWDL et les données multicast restent à 12 Mbit/s, car tous les pairs doivent les recevoir. Le script passe `TX_MCS`, 4 par défaut.
- Preuves : la même vidéo de 6,9 Mo part en 11,5 s à 12 Mbit/s (0,60 Mo/s), en 5,8 s en MCS 4 (1,20 Mo/s) et en 5,3 s en MCS 7 (1,30 Mo/s). La capture Wi-Fi montre les trames de données au débit demandé (essais 39 à 41).
- Le débit plafonne comme en réception. Explication probable : AWDL ne passe qu'une partie de son temps sur le canal 149. MCS 4 est gardé par défaut, presque aussi rapide que MCS 7 et plus tolérant à la distance.
- Date : 2026-11-25
- Produit par : `sudo IFACE=wlp4s0f4u1 CAPTURE=1 TX_MCS=4 bash scripts/airdrop-poc.sh send FICHIER`

### R13

**Un iPad refuse le certificat client autosigné d'OpenDrop, même en "Tout le monde", mais accepte une connexion sans certificat client.**

- Preuves : l'iPad envoie au PC sans difficulté (essai 42). Dans l'autre sens, il est trouvé dans les trames AWDL, puis répond à `/Discover` par l'alerte TLS `bad_certificate` (essai 43). Un certificat "feuille" (`CA:FALSE`, `clientAuth`) n'y change rien (essai 44).
- Diagnostic (essai 45, modifications temporaires non gardées) : en TLS 1.2, l'iPad demande un certificat client (RSA ou ECDSA, sans autorité imposée) et accepte la signature `rsa_pss_rsae_sha256`, puis rejette notre certificat. Lui-même présente un certificat émis par Apple, lié à un compte. Sans certificat client, l'iPad est trouvé. Avec le certificat, toujours en "Tout le monde", il le refuse.
- Correctif : `patches/opendrop-send-ios.patch` se connecte au récepteur sans certificat client (TLS 1.2 minimum, certificat du récepteur non vérifié, comme OpenDrop le faisait). La réception garde le certificat, que l'iPad accepte quand le PC est serveur.
- Résultat : un fichier texte et une photo HEIC envoyés à l'iPad, une photo envoyée à l'iPhone, qui accepte aussi la connexion sans certificat (essai 46).
- Défaut secondaire non corrigé : si `find` ne trouve aucun récepteur, `send` s'arrête sur une `TypeError` dans `_get_receiver_info` d'OpenDrop.
- Date : 2026-11-25
- Produit par : `sudo IFACE=wlp4s0f4u1 CAPTURE=1 bash scripts/airdrop-poc.sh send FICHIER`

## Essais

Les dates exactes des essais 1 à 14 n'ont pas été notées. Ils ont tous été faits au plus tard le 2026-11-13, date du commit qui les décrit. Les essais 15 à 46 utilisent la clé USB MT7612U, les essais 42 à 46 un iPad.

| # | Date | Essai | Résultat | Conclusion |
|---|---|---|---|---|
| 1 | inconnue | Injection, canal 6 (`aireplay-ng --test`) | "No Answer, Found 0 APs" | Non concluant |
| 2 | inconnue | Injection, canal 157 | "Injection is working!", 6 points d'accès | L'injection fonctionne en 5 GHz |
| 3 | inconnue | OWL avec ses réglages par défaut | `Could not put device in monitor mode` | Pas de mode moniteur actif dans `rtw89` |
| 4 | inconnue | OWL en mode moniteur simple (`-N`), canal 149 | `awdl0` créé, aucun pair | L'iPhone n'est pas vu |
| 5 | inconnue | Scan passif sur 6, 44, 149 et 157 | 157 : environ 900 trames, les autres : 0 à 1 | La carte ne reçoit pas sur ces canaux |
| 6 | inconnue | Réception canal par canal (6, 11, 48, 112, 149, 157) | Seul le 157 reçoit, alors que des points d'accès émettent sur 6, 48 et 112 | La carte ne reçoit que sur le dernier canal utilisé par le firmware |
| 7 | inconnue | Point d'accès éphémère, puis mode moniteur | Réception sur 149, 44 et 6, trames AWDL décodées | Contournement trouvé |
| 8 | inconnue | OWL avec les deux contournements, canal 149 | `add peer`, synchronisation avec l'iPhone | La couche AWDL fonctionne |
| 9 | inconnue | `find`, feuille de partage ouverte sur l'iPhone | Aucun appareil trouvé | Limite connue d'OpenDrop : pas d'annonce Bluetooth LE pour réveiller le récepteur |
| 10 | inconnue | `receive` | `Address not available when binding to (fe80::..., 5353...)` | `zeroconf` ne peut pas s'attacher à une adresse IPv6 encore "tentative" et abandonne `awdl0` : le script attend maintenant la fin de la détection d'adresse dupliquée |
| 11 | inconnue | `receive`, `OWL_ARGS="-f -vv"` | L'iPhone voit "poc", ouvre une connexion TLS et envoie `POST /Discover`. OpenDrop plante (`Content-Length` absent) | Seul essai où la réponse TLS du PC est passée. Correctif `patches/opendrop-request-body.patch` |
| 12 | inconnue | `receive`, `OWL_ARGS="-f -vv"`, deux fois | Aucune donnée de l'iPhone. OWL bascule plusieurs fois entre l'iPhone (-37 dBm) et un appareil lointain (-87 dBm) | `-f` (pas de filtre RSSI) fait suivre à OWL des appareils trop lointains |
| 13 | inconnue | `receive`, sans `-f` | Synchronisation stable, 7 connexions TLS de l'iPhone, aucune réponse du PC acquittée | L'iPhone reçoit nos petits paquets (SYN-ACK) mais pas la réponse TLS |
| 14 | inconnue | `receive`, sans `-f`, `TCP_MSS=500` | Réponse TLS découpée en segments de 488 octets, toujours rien d'acquitté | La taille des segments n'est pas la cause |
| 15 | 2026-11-25 | Clé en mode moniteur actif, canaux 6, 44 et 149 | Toutes les trames reçues sont à 2412 MHz. Injection sans réponse | La clé ne change pas de canal dans ce mode |
| 16 | 2026-11-25 | Changement de canal en mode simple, puis actif (4 variantes) | Simple : 6 donne 2437 MHz, 149 donne 5745 MHz. Actif : toujours 2412 MHz | Le mode simple n'a pas besoin du point d'accès éphémère |
| 17 | 2026-11-25 | Interface moniteur simple ouverte d'abord, puis interface active | Le canal suit (149, 6, 44). Injection : "Injection is working!" sur 6, 44 et 149, 83 à 100 % de réponses des points d'accès | Montage trouvé pour le mode actif |
| 18 | 2026-11-25 | Écoute des canaux 149 et 6, feuille de partage ouverte | 289 trames AWDL de l'iPhone en 26 s sur 149, 116 sur 6, entre -24 et -34 dBm | La clé reçoit l'iPhone sans contournement |
| 19 | 2026-11-25 | `receive` avec `ACTIVE_MONITOR=1`, 160 s | `add peer`, 1586 trames AWDL de l'iPhone, 3885 émises par OWL, aucune donnée de l'iPhone, "poc" invisible | Le mode actif bloque l'échange |
| 20 | 2026-11-25 | `receive` sur la clé en mode moniteur simple | "poc" visible, 3 connexions TLS, environ 3,3 Ko acquittés par connexion. OpenDrop refuse `/Upload` (`Unsupported content-type: application/x-dvzip`) | Les réponses du PC passent. Format de fichier inconnu |
| 21 | 2026-11-25 | Même essai, OpenDrop accepte `x-dvzip` et garde la copie brute | 3,76 Mo reçus, extraction échouée. Décodage à la main : archive cpio avec la photo intacte | Format `x-dvzip` compris |
| 22 | 2026-11-25 | Même essai, avec le décodage dans OpenDrop. Puis feuille fermée et rouverte | Photo de 3,59 Mo extraite à 0,93 Mo/s, "Envoyé" sur l'iPhone. Ensuite, OWL retrouve l'iPhone, mais l'iPhone n'envoie plus rien et ne revoit pas "poc" | Premier fichier reçu sans intervention. Il manque une réannonce |
| 23 | 2026-11-25 | `receive` avec la réannonce sur `add peer`. Une image, feuille fermée puis rouverte, un deuxième fichier | Image PNG de 347 Ko reçue (0,44 Mo/s). Après la réouverture, `Re-announcing service`, "poc" réapparaît et un PDF de 6 Ko est reçu (un fichier texte converti par l'iPhone). Fichiers `._nom` en plus | La réannonce suffit. Fichiers AppleDouble à ignorer
| 24 | 2026-11-25 | Capacités média d'un Mac annoncées (`opendrop-media-capabilities.patch`). Deux photos, une Live Photo, une vidéo HEVC | `ConvertMediaFormats = False`. Photos en HEIC (1,06 Mo/s). Live Photo en image fixe seule. Vidéo réencodée en H.264 1080p pendant l'envoi | Photos d'origine. Vidéos et Live Photos encore converties |
| 25 | 2026-11-25 | Annonce élargie (HEVC niveau 186, Dolby Vision `dvh1`, macOS 15.1), plus l'option iOS "Toutes les données des photos" | Vidéo toujours en H.264, Live Photo toujours en image fixe, 0,97 à 1,09 Mo/s. Un deuxième envoi du même fichier écrase le premier | L'annonce élargie ne change rien |
| 26 | 2026-11-25 | Clé sans point d'accès éphémère. Même photo deux fois, puis 20 photos d'un coup | "poc" visible. `IMG_4913.HEIC` puis `IMG_4913 (2).HEIC`. 39,08 Mo à 1,19 Mo/s, chaque fichier dans un dossier `NSIRD_AirDrop_xxxxxx/`. "poc" disparaît après les deux envois (journaux perdus à la relance) | Le point d'accès n'est plus nécessaire. Dossiers temporaires à retirer |
| 27 | 2026-11-25 | Même scénario, journaux gardés par run | 1er lancement : OpenDrop s'arrête (`NonUniqueNameException`), le signal est arrivé pendant l'enregistrement du service. Puis deux envois, et "poc" disparaît quand l'iPhone rouvre sa feuille sans quitter AWDL. Puis 5 photos à 1,08 Mo/s, rangées directement dans `out/received/` | Il faut attendre l'enregistrement, et réannoncer aussi sur `changed channel sequence` |
| 28 | 2026-11-25 | Réannonce après `Service announced`, sur `add peer` ou `changed channel sequence` | Quatre envois de la même photo sans relancer, "poc" réapparaît à chaque fois, 6 réannonces, 0,99 à 1,30 Mo/s | Réannonce fiable |
| 29 | 2026-11-25 | `find` avec l'annonce Bluetooth LE d'AirDrop, iPhone écran allumé, feuille fermée | L'iPhone allume AWDL (`add peer`), mais ne répond pas aux requêtes mDNS. Il annonce `_airdrop._tcp` dans ses trames AWDL (SRV port 8770, TXT `flags`) | L'annonce Bluetooth réveille l'iPhone. Il faut lire les trames AWDL |
| 30 | 2026-11-25 | Lecture des TLV par `tshark`, `--peers-file` dans OpenDrop | Récepteur trouvé, puis `TypeError` dans `HTTPSConnection` (`key_file`) | OpenDrop incompatible avec Python 3.12 et plus |
| 31 | 2026-11-25 | `opendrop-compat.patch`, `find` puis `send` d'un fichier texte | `find` affiche l'iPhone et son nom. `send` : l'iPhone accepte, puis `TypeError` dans `ArchiveEntry` | OpenDrop incompatible avec libarchive-c 5 |
| 32 | 2026-11-25 | Envoi corrigé, en `x-cpio` compressé puis en `x-dvzip` | L'iPhone accuse réception en TCP mais ne répond pas à `/Upload`. Barre de progression figée | Il manque des informations sur le transfert |
| 33 | 2026-11-25 | `opendrop-send-ios.patch` : tailles et identifiant de transfert. Texte, puis photo HEIC | `Uploading has been successful`. Texte ouvert dans Fichiers. Photo de 2,94 Mo en 4,9 s (0,60 Mo/s), ouverte dans Fichiers | Premier envoi du PC vers l'iPhone |
| 34 | 2026-11-25 | Type de fichier d'après l'extension, `Image.LANCZOS` au lieu de `Image.ANTIALIAS`. Une photo HEIC, puis une JPEG | `Uploading has been successful` deux fois. Les deux photos s'ouvrent dans Photos | Le type déclaré décide de l'application |
| 35 | 2026-11-25 | Modèle annoncé `MacBookPro18,1` (`-m`), capacités de macOS 10.13 | Vidéo toujours en H.264, Live Photo toujours en image fixe | Le modèle seul ne change rien |
| 36 | 2026-11-25 | `find` avec `-d`, iPhone récepteur | Réponse `/Discover` de l'iPhone enregistrée, avec ses capacités média au format d'iOS 26 (`Version` 3, `VTMaxDecodeLevel`, Dolby Vision) | Format de référence trouvé |
| 37 | 2026-11-25 | Capacités d'iOS 26 recopiées à l'identique. Une Live Photo, une vidéo HEVC | Vidéo en HEVC d'origine (HDR, 3,98 Mo). Live Photo en image fixe, l'iPhone ne propose que le HEIC | Vidéos d'origine. Live Photos toujours incomplètes |
| 38 | 2026-11-25 | Mêmes capacités et modèle `MacBookPro18,1`. Une Live Photo | Toujours l'image fixe seule | Le modèle ne débloque pas les Live Photos |
| 39 | 2026-11-25 | Envoi d'une vidéo de 6,9 Mo à 12 Mbit/s (comportement d'origine d'OWL) | 11,5 s, 0,60 Mo/s, 17 retransmissions TCP | Référence |
| 40 | 2026-11-25 | Même envoi, `TX_MCS=4` (39 Mbit/s) | 5,8 s, 1,20 Mo/s, 9 retransmissions TCP | Débit doublé |
| 41 | 2026-11-25 | Même envoi, `TX_MCS=7` (65 Mbit/s) | 5,3 s, 1,30 Mo/s, 11 retransmissions TCP | Gain faible au-delà de MCS 4 |
| 42 | 2026-11-25 | `receive`, envoi depuis un iPad | Une image WEBP de 199 Ko reçue | La réception marche avec l'iPad |
| 43 | 2026-11-25 | `send` vers l'iPad | iPad trouvé dans les trames AWDL, puis alerte TLS `bad_certificate` sur `/Discover`. À la relance, connexion refusée | L'iPad refuse notre certificat client |
| 44 | 2026-11-25 | Certificat "feuille" (`CA:FALSE`, `clientAuth`, même clé) | Toujours `bad_certificate` | La forme du certificat n'est pas en cause. Certificat d'origine remis |
| 45 | 2026-11-25 | Diagnostics temporaires : TLS 1.2 forcé, puis sans certificat client, puis avec | Demande de certificat lisible, sans autorité imposée. Sans certificat : iPad trouvé. Avec : `bad_certificate`, iPad toujours en "Tout le monde" | L'iPad refuse un certificat autosigné, accepte l'absence de certificat |
| 46 | 2026-11-25 | Envoi sans certificat client (`opendrop-send-ios.patch`) | Texte et photo HEIC envoyés à l'iPad, photo envoyée à l'iPhone, `Uploading has been successful` à chaque fois | Envoi validé sur les deux appareils |

## Pistes écartées

- **Filtre `tcpdump` écrit à la main pour repérer les trames AWDL** : il ne trouvait rien. Le dissecteur `awdl` de `tshark` le remplace. Avec la clé, les filtres sur le type de trame (`subtype action`) ou sur un octet (`wlan[24]`) ne trouvent rien non plus, alors que les trames sont dans la capture (essai 18). Le filtre sur le BSSID d'AWDL, celui qu'utilise OWL, fonctionne : `wlan addr3 00:25:00:ff:94:73`.
- **Annonce élargie des formats** : HEVC jusqu'au niveau 6.2, Dolby Vision (`dvh1`) et macOS 15.1, écrits à la main, ne changent rien aux vidéos ni aux Live Photos (essai 25). Les capacités recopiées depuis l'iPhone les remplacent ([R10](#r10)).
- **Modèle annoncé (`-m MacBookPro18,1`)** : sans effet sur les vidéos ni sur les Live Photos (essais 35 et 38).
- **Mode moniteur actif de la MT7612U** : la clé change de canal avec le montage de [R7](#r7), mais l'iPhone ne lui envoie rien (essai 19). L'option `ACTIVE_MONITOR` est gardée, désactivée par défaut.
- **OWL sans filtre RSSI (`-f`)** : OWL suit alors des appareils trop lointains et perd l'iPhone (essai 12).
- **Limiter la taille des segments TCP (`TCP_MSS`)** : avec `TCP_MSS=500`, le script réécrit l'option MSS des SYN reçus de l'iPhone (règle nftables dans la table `airdrop_poc`, supprimée à la sortie). L'essai 14 montre que ça ne suffit pas. L'option est gardée mais désactivée par défaut.

```bash
nft add table inet airdrop_poc
nft add chain inet airdrop_poc prerouting '{ type filter hook prerouting priority mangle; }'
nft add rule inet airdrop_poc prerouting iifname awdl0 'tcp flags & (syn | ack) == syn' tcp option maxseg size set 500
```

## Questions ouvertes

- **Pourquoi les Live Photos arrivent-elles sans leur vidéo ?** L'iPhone le décide d'après la réponse à `/Discover`, mais ni les capacités d'iOS 26 ni le modèle n'y changent rien. Il faut peut-être un appareil connu ou un contact. Je n'ai pas de moyen direct de le tester.
- **Pourquoi l'iPhone n'envoie-t-il rien en mode moniteur actif ?** Piste : comparer les trames émises par OWL dans les deux modes (débit, drapeaux radiotap, moment d'émission).
