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
- [Essais](#essais)
- [Pistes écartées](#pistes-écartées)
- [Questions ouvertes](#questions-ouvertes)

## Résumé

Sur une RTL8852BE, la couche AWDL fonctionne avec deux contournements : pas de mode moniteur actif, et une réception limitée au dernier canal utilisé par le firmware. L'iPhone voit alors le PC et ouvre des connexions TLS, mais les réponses du PC se perdent.

Avec une clé USB MT7612U en mode moniteur simple, les réponses du PC arrivent et le PC reçoit des photos de l'iPhone. La carte était donc bien en cause. Le mode moniteur actif de la clé empêche au contraire l'iPhone d'envoyer des données. Les iOS récents envoient les fichiers au format `x-dvzip`, une suite de blocs zlib autour de l'archive cpio habituelle.

## Méthode

Matériel et logiciels : voir [Matériel](README.md#matériel) dans le README.

Le script `scripts/airdrop-poc.sh` :

1. avec une carte `rtw89`, lance un point d'accès éphémère sur le canal 149, puis le coupe (contournement de [R2](#r2)). Avec un autre pilote, comme `mt76x2u`, cette étape est sautée ;
2. passe la carte en mode moniteur simple sur ce canal (contournement de [R1](#r1)) ;
3. démarre OWL en arrière-plan et attend que `awdl0` ait une adresse IPv6 ;
4. lance OpenDrop sur `awdl0`, avec les droits de l'utilisateur ;
5. en `receive`, demande à OpenDrop de réannoncer son service quand l'iPhone commence une nouvelle recherche ([R9](#r9)) ;
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

**`find` et `send` ne trouvent pas l'iPhone.**

- Preuves : avec la feuille de partage ouverte sur l'iPhone, `find` ne trouve aucun appareil (essai 9). L'iPhone n'ouvre son serveur AirDrop qu'après une annonce Bluetooth LE, qu'OpenDrop ne sait pas faire. C'est une limite connue d'OpenDrop.
- Date : inconnue
- Produit par : `sudo bash scripts/airdrop-poc.sh find`

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

**En annonçant les formats d'un Mac, le PC reçoit les photos en HEIC. Les vidéos HEVC restent converties en H.264, et les Live Photos arrivent sans leur vidéo.**

- Preuves : avec les capacités média relevées sur macOS 10.13.3 (HEVC, HEIF/HEIC, Live Photos), la demande d'envoi de l'iPhone indique `ConvertMediaFormats = False` et deux photos arrivent en HEIC (essai 24). Une vidéo HEVC d'après l'iPhone arrive en H.264, 1080p, 30 images/s : sa date `creation_time` est celle de l'envoi, alors que `com.apple.quicktime.creationdate` est celle du tournage, donc l'iPhone la réencode pendant l'envoi. Une Live Photo arrive en image fixe seule (essais 24 et 25).
- Débit : 0,97 à 1,09 Mo/s par fichier, mesuré par OpenDrop (essais 24 et 25).
- Hypothèse non testée : OpenDrop se présente avec `ReceiverModelName = OpenDrop`. L'iPhone pourrait choisir les formats d'après ce modèle. OpenDrop permet de le changer avec son option `-m`.
- Date : 2026-11-25
- Produit par : `patches/opendrop-media-capabilities.patch`, puis `sudo IFACE=wlp4s0f4u1 CAPTURE=1 OPENDROP_ARGS="-d" bash scripts/airdrop-poc.sh receive` (`-d` enregistre les requêtes de l'iPhone dans `~/.opendrop/debug/`)

## Essais

Les dates exactes des essais 1 à 14 n'ont pas été notées. Ils ont tous été faits au plus tard le 2026-11-13, date du commit qui les décrit. Les essais 15 à 28 utilisent la clé USB MT7612U.

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

## Pistes écartées

- **Filtre `tcpdump` écrit à la main pour repérer les trames AWDL** : il ne trouvait rien. Le dissecteur `awdl` de `tshark` le remplace. Avec la clé, les filtres sur le type de trame (`subtype action`) ou sur un octet (`wlan[24]`) ne trouvent rien non plus, alors que les trames sont dans la capture (essai 18). Le filtre sur le BSSID d'AWDL, celui qu'utilise OWL, fonctionne : `wlan addr3 00:25:00:ff:94:73`.
- **Annonce élargie des formats** : HEVC jusqu'au niveau 6.2, Dolby Vision (`dvh1`) et macOS 15.1 ne changent rien aux vidéos ni aux Live Photos (essai 25). Le correctif garde les valeurs relevées sur un Mac.
- **Mode moniteur actif de la MT7612U** : la clé change de canal avec le montage de [R7](#r7), mais l'iPhone ne lui envoie rien (essai 19). L'option `ACTIVE_MONITOR` est gardée, désactivée par défaut.
- **OWL sans filtre RSSI (`-f`)** : OWL suit alors des appareils trop lointains et perd l'iPhone (essai 12).
- **Limiter la taille des segments TCP (`TCP_MSS`)** : avec `TCP_MSS=500`, le script réécrit l'option MSS des SYN reçus de l'iPhone (règle nftables dans la table `airdrop_poc`, supprimée à la sortie). L'essai 14 montre que ça ne suffit pas. L'option est gardée mais désactivée par défaut.

```bash
nft add table inet airdrop_poc
nft add chain inet airdrop_poc prerouting '{ type filter hook prerouting priority mangle; }'
nft add rule inet airdrop_poc prerouting iifname awdl0 'tcp flags & (syn | ack) == syn' tcp option maxseg size set 500
```

## Questions ouvertes

- **Comment recevoir les vidéos HEVC et les Live Photos d'origine ?** Essai prévu : changer le modèle annoncé avec `OPENDROP_ARGS="-m <modèle de Mac>"`, puis envoyer une vidéo et une Live Photo.
- **Pourquoi l'iPhone n'envoie-t-il rien en mode moniteur actif ?** Piste : comparer les trames émises par OWL dans les deux modes (débit, drapeaux radiotap, moment d'émission).
