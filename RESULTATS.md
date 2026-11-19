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
- [Essais](#essais)
- [Pistes écartées](#pistes-écartées)
- [Questions ouvertes](#questions-ouvertes)

## Résumé

Sur une RTL8852BE, la couche AWDL fonctionne avec deux contournements : pas de mode moniteur actif, et une réception limitée au dernier canal utilisé par le firmware. L'iPhone voit alors le PC et ouvre des connexions TLS. Les réponses du PC se perdent, et aucun fichier n'a été reçu. Les captures pointent vers la carte, qui n'acquitte rien et n'émet chaque trame qu'une fois.

## Méthode

Matériel et logiciels : voir [Matériel](README.md#matériel) dans le README.

Le script `scripts/airdrop-poc.sh` :

1. lance un point d'accès éphémère sur le canal 149, puis le coupe (contournement de [R2](#r2)) ;
2. passe la carte en mode moniteur simple sur ce canal (contournement de [R1](#r1)) ;
3. démarre OWL en arrière-plan et attend que `awdl0` ait une adresse IPv6 ;
4. lance OpenDrop sur `awdl0`, avec les droits de l'utilisateur ;
5. à la sortie (fin normale, erreur ou Ctrl+C), arrête OWL, supprime le point d'accès et remet la carte en Wi-Fi normal.

Observation :

- journaux d'OWL (`out/owl.log`) et d'OpenDrop (`out/opendrop.log`) ;
- avec `CAPTURE=1`, captures de `awdl0` (`out/awdl0.pcap`) et des trames Wi-Fi brutes (`out/wlan.pcap`), résumées par `scripts/diagnostics/summarize-run.sh` ;
- les trames AWDL sont repérées avec le dissecteur `awdl` de `tshark` ;
- les scripts de `scripts/diagnostics/` ont servi aux essais 1 à 8 (injection, scan passif, réception canal par canal, astuce du point d'accès, OWL au premier plan).

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
- Date : inconnue
- Produit par : `sudo CAPTURE=1 bash scripts/airdrop-poc.sh receive`, puis `bash scripts/diagnostics/summarize-run.sh`

### R5

**`find` et `send` ne trouvent pas l'iPhone.**

- Preuves : avec la feuille de partage ouverte sur l'iPhone, `find` ne trouve aucun appareil (essai 9). L'iPhone n'ouvre son serveur AirDrop qu'après une annonce Bluetooth LE, qu'OpenDrop ne sait pas faire. C'est une limite connue d'OpenDrop.
- Date : inconnue
- Produit par : `sudo bash scripts/airdrop-poc.sh find`

## Essais

Les dates exactes des essais n'ont pas été notées. Ils ont tous été faits au plus tard le 2026-11-13, date du commit qui les décrit.

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

## Pistes écartées

- **Filtre `tcpdump` écrit à la main pour repérer les trames AWDL** : il ne trouvait rien. Le dissecteur `awdl` de `tshark` le remplace.
- **OWL sans filtre RSSI (`-f`)** : OWL suit alors des appareils trop lointains et perd l'iPhone (essai 12).
- **Limiter la taille des segments TCP (`TCP_MSS`)** : avec `TCP_MSS=500`, le script réécrit l'option MSS des SYN reçus de l'iPhone (règle nftables dans la table `airdrop_poc`, supprimée à la sortie). L'essai 14 montre que ça ne suffit pas. L'option est gardée mais désactivée par défaut.

```bash
nft add table inet airdrop_poc
nft add chain inet airdrop_poc prerouting '{ type filter hook prerouting priority mangle; }'
nft add rule inet airdrop_poc prerouting iifname awdl0 'tcp flags & (syn | ack) == syn' tcp option maxseg size set 500
```

## Questions ouvertes

- **La carte est-elle la cause des pertes ?** Ma piste principale est le moment d'émission : si le firmware émet les trames injectées en retard, elles tombent hors des courtes fenêtres où l'iPhone écoute le canal. Une carte avec un autre pilote permet de trancher. J'ai commandé une clé USB COMFAST CF-922AC, à puce MediaTek MT7612U (pilote `mt76x2u` du noyau). Essai prévu à sa réception :
  1. vérifier la puce et ses capacités (`lsusb`, `iw list | grep -i "active monitor"`) ;
  2. refaire le test d'injection et la réception sur les canaux 6, 44 et 149, pour savoir si les contournements de R1 et R2 sont encore nécessaires ;
  3. relancer `receive` avec `IFACE=<interface de la clé>` et comparer avec l'essai 13, en regardant d'abord si l'iPhone acquitte les réponses du PC ;
  4. si ça passe, recevoir un premier fichier, puis mesurer le débit.
- **Peut-on garder le Wi-Fi habituel pendant les essais ?** Avec une clé USB, la carte interne reste connectée pendant qu'AWDL tourne sur la clé. À vérifier pendant l'essai avec la MT7612U.
