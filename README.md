# awdl-linux-poc : AirDrop sur mon PC Linux

Preuve de concept : savoir si ce PC (Fedora, carte Wi-Fi Realtek RTL8852BE) peut
échanger des fichiers en **vrai AirDrop** avec un iPhone, sans application côté Apple.

Ce dépôt ne contient pas de produit fini. J'y rassemble mes essais, leurs résultats,
les contournements que j'ai trouvés et un script pour refaire le test.

## Où j'en suis

| Étape | État |
|-------|------|
| La carte Wi-Fi peut injecter des trames | Oui, en 5 GHz (canal 157) |
| La carte reçoit le trafic AWDL des appareils Apple | Oui, avec l'astuce du point d'accès (voir plus bas) |
| OWL crée l'interface `awdl0` et se synchronise avec un iPhone | **Oui** : pair détecté (`add peer`), OWL rejoint l'élection AWDL |
| OpenDrop voit l'iPhone (`find`) | À tester |
| Recevoir un fichier depuis l'iPhone (`receive`) | À tester |
| Envoyer un fichier vers l'iPhone (`send`) | À tester |

La couche basse (AWDL) fonctionne. Il me reste à valider la couche AirDrop elle-même,
avec un vrai transfert.

## Comment marche AirDrop

AirDrop empile plusieurs briques :

1. **Bluetooth Low Energy** : annonce la présence de l'appareil et réveille les voisins.
2. **AWDL** (Apple Wireless Direct Link) : un réseau Wi-Fi pair à pair propriétaire
   d'Apple, sans point d'accès. Il fonctionne sur les canaux 6 (2,4 GHz), 44 et 149 (5 GHz).
3. **mDNS / DNS-SD** sur AWDL : découverte du service `_airdrop._tcp`.
4. **HTTPS** (port 8771 côté OpenDrop) : échange d'identité puis envoi du fichier
   sous forme d'archive.

Deux projets du [Secure Mobile Networking Lab](https://owlink.org/) (TU Darmstadt) ont
réimplémenté ces briques :

- [OWL](https://github.com/seemoo-lab/owl) (C) implémente AWDL et crée une interface
  réseau `awdl0` ;
- [OpenDrop](https://github.com/seemoo-lab/opendrop) (Python) implémente le protocole
  AirDrop (points 3 et 4) par-dessus `awdl0`.

OpenDrop ne fait pas l'annonce Bluetooth : l'iPhone doit avoir la feuille de partage
AirDrop ouverte pour activer AWDL et voir le PC.

## Machine de test

- Fedora 44, noyau 7.2.15
- Carte Wi-Fi Realtek **RTL8852BE** (PCIe, 802.11ax), pilote `rtw89_8852be`,
  firmware 0.29.29.18 (`linux-firmware-20261019`), interface `wlp2s0`
- mon iPhone, réglé sur AirDrop « Tout le monde »

## Ce qu'il faut à la carte Wi-Fi

OWL demande bien plus qu'une connexion Wi-Fi classique :

- le **mode moniteur**, pour recevoir toutes les trames du canal ;
- l'**injection de trames**, pour émettre des trames AWDL ;
- idéalement le **mode moniteur actif**, où la carte acquitte (ACK) les trames qui lui
  sont destinées. Sans lui, l'émetteur retransmet chaque trame jusqu'à 7 fois et le
  débit chute ;
- la réception sur un **canal AWDL** : 6, 44 ou 149.

Pour vérifier une carte :

```sh
# "monitor" doit apparaître
iw list | grep -A10 "Supported interface modes"

# Mode moniteur actif : la ligne doit apparaître
iw phy phy0 info | grep -i "active monitor"

# Les canaux 6, 44 et 149 ne doivent être ni "disabled" ni "no IR"
iw list | grep -E "\[(6|44|149)\]"

# Injection (paquet aircrack-ng), carte en mode moniteur sur un canal avec des AP à portée
sudo aireplay-ng --test wlp2s0
```

## Ce que j'ai testé

J'ai mené les essais dans l'ordre ci-dessous. Les scripts correspondants sont dans
`scripts/diagnostics/`.

| # | Essai | Résultat | Conclusion |
|---|-------|----------|------------|
| 1 | Injection, canal 6 (`aireplay-ng --test`) | « No Answer, Found 0 APs » | Non concluant |
| 2 | Injection, canal 157 | « Injection is working! », 6 AP | L'injection marche en 5 GHz |
| 3 | OWL, réglages par défaut | `Could not put device in monitor mode` (`Operation not supported`) | rtw89 n'a pas de mode moniteur **actif** |
| 4 | OWL en mode moniteur simple (`-N`), canal 149 | OWL démarre, `awdl0` créé, aucun pair | L'iPhone n'est pas vu |
| 5 | Scan passif sur 6 / 44 / 149 / 157 | 157 : ~900 trames ; les autres : 0 à 1 | La carte ne reçoit pas sur ces canaux |
| 6 | Réception canal par canal (6, 11, 48, 112, 149, 157) | Seul le 157 reçoit, alors que des AP émettent sur 6, 48 et 112 | **Bug confirmé** : en mode moniteur, la carte ne reçoit que sur le canal où le firmware travaillait juste avant |
| 7 | Point d'accès éphémère sur le canal, puis mode moniteur | Réception OK sur 149, 44 et 6 ; trames AWDL décodées par `tshark` | J'ai trouvé un contournement |
| 8 | OWL avec les deux contournements, canal 149 | **`add peer`**, synchronisation AWDL avec l'iPhone | La chaîne AWDL marche sur cette carte |

Remarques :

- Un filtre `tcpdump` écrit à la main pour les trames AWDL ne trouvait rien. Le
  dissecteur `awdl` de `tshark` (paquet `wireshark-cli`) les trouve. J'utilise donc
  `tshark`.
- Les appareils Apple utilisent des adresses MAC aléatoires et des noms d'hôte en UUID :
  je ne peux pas toujours savoir lequel est mon iPhone.
- L'iPhone suivait la séquence de canaux 48 / 149 / 6. OWL reste sur un seul canal
  (le 149), ce qui suffit pour se synchroniser.

## Les deux contournements pour la RTL8852BE

**1. Pas de mode moniteur actif.** Passer soi-même la carte en mode moniteur simple,
puis lancer OWL avec `-N` pour qu'il ne touche pas à la configuration :

```sh
ip link set wlp2s0 down
iw dev wlp2s0 set type monitor
ip link set wlp2s0 up
owl -i wlp2s0 -c 149 -N
```

Contrepartie : sans ACK, il faut s'attendre à un débit de transfert dégradé.

**2. Réception limitée à un canal.** Avant le mode moniteur, faire travailler le
firmware sur le canal AWDL voulu avec un point d'accès éphémère :

```sh
nmcli device wifi hotspot ifname wlp2s0 band a channel 149 ssid poc-tmp password <mdp>
nmcli connection down Hotspot
nmcli device set wlp2s0 managed no
# puis le contournement 1, et :
iw dev wlp2s0 set channel 149
```

Ce comportement du firmware n'est pas documenté : une mise à jour du noyau ou du
firmware peut le corriger, ou au contraire casser le contournement.

## Refaire le test

### Prérequis

```sh
# Outils et dépendances de compilation d'OWL (Fedora)
sudo dnf install cmake libpcap-devel libev-devel libnl3-devel wireshark-cli aircrack-ng

# OWL, compilé hors du dépôt
git clone --recursive https://github.com/seemoo-lab/owl.git ~/.local/src/owl
cmake -S ~/.local/src/owl -B ~/.local/src/owl/build -DCMAKE_POLICY_VERSION_MINIMUM=3.5
make -C ~/.local/src/owl/build owl

# OpenDrop, dans un venv à la racine du dépôt
python3 -m venv .venv
.venv/bin/pip install opendrop "setuptools<81"
```

Points connus :

- `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` est nécessaire avec CMake 4, à cause des
  sous-modules d'OWL ;
- je compile seulement la cible `owl` : les tests d'OWL (googletest) ne compilent plus
  avec un GCC récent, ce qui n'affecte pas le binaire ;
- `setuptools<81` est nécessaire parce qu'OpenDrop importe encore `pkg_resources`, qui
  n'existe plus dans les environnements Python récents (testé avec Python 3.14) ;
- le pare-feu de Fedora Workstation laisse passer les ports 1025 à 65535, donc 8771
  et mDNS passent sans réglage.

### Lancer

Depuis la racine du dépôt, iPhone en AirDrop « Tout le monde », feuille de partage
ouverte :

```sh
sudo bash scripts/airdrop-poc.sh find          # lister les appareils AirDrop à portée
sudo bash scripts/airdrop-poc.sh receive       # être visible et recevoir des fichiers
sudo bash scripts/airdrop-poc.sh send FICHIER  # chercher 30 s puis envoyer à l'appareil 0
```

Le script :

1. lance un point d'accès éphémère sur le canal 149, puis le coupe (contournement 2) ;
2. passe la carte en mode moniteur simple sur le canal 149 (contournement 1) ;
3. démarre OWL en arrière-plan et attend que `awdl0` ait une adresse IPv6 ;
4. lance OpenDrop sur `awdl0` avec tes droits d'utilisateur ;
5. à la sortie (fin normale, erreur ou Ctrl+C), arrête OWL, supprime le point d'accès
   et remet la carte en Wi-Fi normal.

Le Wi-Fi habituel est coupé pendant l'essai.

| Variable | Défaut | Rôle |
|----------|--------|------|
| `IFACE` | `wlp2s0` | Interface Wi-Fi |
| `CHANNEL` | `149` | Canal AWDL (44 ou 6 possibles) |
| `DEVICE_NAME` | `poc` | Nom affiché sur l'iPhone en mode `receive` |
| `FIND_SECONDS` | `30` | Durée de recherche avant un `send` |
| `OWL_BIN` | `~/.local/src/owl/build/daemon/owl` | Binaire OWL |

Exemple : `sudo CHANNEL=44 bash scripts/airdrop-poc.sh find`.

Résultats dans `out/` (ignoré par git) : `owl.log` pour OWL, `received/` pour les
fichiers reçus. Les clés et le certificat d'OpenDrop sont générés au premier lancement
dans `~/.opendrop/`.

### Scripts de diagnostic

Je les garde pour référence dans `scripts/diagnostics/`. Ils contiennent des chemins
propres à ma machine.

| Script | Rôle |
|--------|------|
| `injection-test-2.sh` | Mode moniteur, réception `tcpdump` puis test d'injection sur le 157 |
| `awdl-scan.sh` | Scan passif des canaux AWDL |
| `channel-test.sh` | Compte les trames reçues canal par canal (a mis le bug en évidence) |
| `hotspot-trick.sh` | Teste l'astuce du point d'accès sur une liste de canaux |
| `owl-test.sh` | OWL au premier plan avec les deux contournements |

## Limites

- **Matériel** : peu de cartes intégrées gèrent le mode moniteur avec injection. Sur
  la mienne, il faut deux contournements non documentés.
- **Wi-Fi coupé** pendant qu'AWDL tourne, parce que la carte lui est dédiée.
- **Côté Apple** : sans certificat signé par Apple, l'iPhone ne voit le PC qu'en mode
  « Tout le monde ». Ce mode se désactive seul au bout de 10 minutes.
- **Projets peu maintenus** : le dernier commit de code d'OWL date de janvier 2022,
  celui d'OpenDrop d'avril 2021. Une mise à jour d'iOS peut tout casser.
- **Droits root** pour le mode moniteur et OWL.

Pour une carte qui marche sans contournement, il faut le mode moniteur actif. L'équipe
d'OWL a développé avec une **Atheros AR9280** (`ath9k`). Côté clés USB, la
**MediaTek MT7612U** (`mt76`, 2,4 et 5 GHz) est réputée compatible, mais je ne l'ai pas
testée.
