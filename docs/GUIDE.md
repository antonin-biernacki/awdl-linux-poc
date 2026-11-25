# Guide

## Installation

Les commandes sont dans [Reproduire](../README.md#reproduire). Points à connaître :

- `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` est nécessaire avec CMake 4, à cause des sous-modules d'OWL ;
- je compile seulement la cible `owl` : les tests d'OWL (googletest) ne compilent plus avec un GCC récent, ce qui n'affecte pas le binaire ;
- `scripts/setup-opendrop.sh` crée l'environnement virtuel `.venv` à la racine du dépôt et y installe OpenDrop 0.13.0 ;
- `setuptools<81` fournit `pkg_resources`, qu'OpenDrop importe encore et qui n'existe plus dans les environnements Python récents (testé avec Python 3.14) ;
- l'iPhone envoie ses requêtes `/Discover` et `/Ask` sans en-tête `Content-Length`, a priori en transfert chunked. OpenDrop 0.13.0 plante alors (`int() argument must be ... not 'NoneType'`). `patches/opendrop-request-body.patch` lui apprend à lire ces requêtes ;
- les iOS récents envoient les fichiers en `application/x-dvzip`, qu'OpenDrop 0.13.0 refuse. `patches/opendrop-dvzip.patch` décode ce format (voir [R8](../RESULTATS.md#r8)) et garde la copie brute dans `out/received/` si l'extraction échoue. Il ignore les fichiers AppleDouble `._nom` (métadonnées macOS) ;
- `patches/opendrop-reannounce.patch` fait réannoncer le service par OpenDrop sur `SIGUSR1`. `scripts/airdrop-poc.sh` l'envoie quand OWL retrouve l'iPhone (voir [R9](../RESULTATS.md#r9)) ;
- `patches/opendrop-media-capabilities.patch` annonce à l'iPhone les formats d'un Mac, pour recevoir les photos en HEIC (voir [R10](../RESULTATS.md#r10)) ;
- `scripts/setup-opendrop.sh` peut être relancé sans risque : il réinstalle OpenDrop d'origine, puis applique tous les correctifs dans l'ordre. Tester chaque correctif à part ne suffit pas, car un correctif peut modifier le contexte d'un autre ;
- le pare-feu de Fedora Workstation ouvre les ports 1025 à 65535, donc le port 8771 d'OpenDrop et le mDNS passent sans réglage ;
- les clés et le certificat d'OpenDrop sont générés au premier lancement dans `~/.opendrop/`.

## Configuration et options

Options de `scripts/airdrop-poc.sh`, à passer en variables d'environnement :

| Variable        | Défaut                              | Rôle |
|-----------------|-------------------------------------|------|
| `IFACE`         | `wlp2s0`                            | Interface Wi-Fi |
| `CHANNEL`       | `149`                               | Canal AWDL (44 ou 6 possibles) |
| `DEVICE_NAME`   | `poc`                               | Nom affiché sur l'iPhone (`receive`) |
| `FIND_SECONDS`  | `30`                                | Durée de recherche avant un `send` |
| `CAPTURE`       | `0`                                 | `1` : enregistre le trafic de `awdl0` (`out/awdl0.pcap`) et les trames Wi-Fi brutes (`out/wlan.pcap`) |
| `OWL_ARGS`      | (vide)                              | Options en plus pour OWL, par exemple `-f -vv` (sans filtre RSSI, journal détaillé) |
| `OPENDROP_ARGS` | (vide)                              | Options en plus pour OpenDrop, par exemple `-d` (débogage) |
| `TCP_MSS`       | `0`                                 | Taille maximale des segments TCP envoyés à l'iPhone (`0` : pas de limite), voir les [pistes écartées](../RESULTATS.md#pistes-écartées) |
| `OWL_BIN`       | `~/.local/src/owl/build/daemon/owl` | Binaire OWL |
| `ACTIVE_MONITOR`| `0`                                 | `1` : mode moniteur actif, sans point d'accès éphémère, avec l'interface d'aide `pocmon0` (voir [R7](../RESULTATS.md#r7)). Avec la MT7612U, l'iPhone n'envoie alors rien |

Exemple :

```bash
sudo CHANNEL=44 bash scripts/airdrop-poc.sh find
```

Fichiers produits dans `out/` (ignoré par git) :

```text
out/
    owl.log        # journal d'OWL
    opendrop.log   # sortie d'OpenDrop
    awdl0.pcap     # trafic de awdl0, avec CAPTURE=1
    wlan.pcap      # trames Wi-Fi brutes, avec CAPTURE=1
    received/      # fichiers reçus
```

Scripts de `scripts/diagnostics/` :

```text
injection-test-2.sh   # réception en mode moniteur et test d'injection (canal 157)
awdl-scan.sh          # scan passif des canaux AWDL
channel-test.sh       # nombre de trames reçues canal par canal
hotspot-trick.sh      # astuce du point d'accès sur une liste de canaux
owl-test.sh           # OWL au premier plan, avec les deux contournements
summarize-run.sh      # résumé du dernier essai (pairs, trames, requêtes, fichiers)
adapter-test.sh       # autre carte (IFACE) : fréquence écoutée, trames AWDL, injection sur 6, 44, 149
```

## Matériel

Pour vérifier une autre carte :

```bash
iw list | grep -A10 "Supported interface modes"
iw phy phy0 info | grep -i "active monitor"
iw list | grep -E "\[(6|44|149)\]"
sudo aireplay-ng --test wlp2s0
```

- La première commande doit afficher "monitor" parmi les modes.
- La deuxième indique si la carte gère le mode moniteur actif.
- La troisième ne doit afficher ni "disabled" ni "no IR" pour les canaux 6, 44 et 149.
- La quatrième teste l'injection, avec la carte en mode moniteur.

Pour une clé USB, `adapter-test.sh` fait ces vérifications canal par canal, sans toucher à la carte intégrée. Garder la feuille de partage ouverte sur l'iPhone pendant le test :

```bash
sudo IFACE=wlp4s0f4u1 bash scripts/diagnostics/adapter-test.sh
```

Le résultat est enregistré dans `out/adapter-test.txt`.
