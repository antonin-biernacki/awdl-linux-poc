# Preuve de concept

Objectif : réussir un vrai transfert AirDrop entre ce PC et un iPhone avant d'écrire
le daemon et l'extension. La chaîne testée est celle décrite dans
[docs/hardware.md](../docs/hardware.md) : OWL fournit l'interface `awdl0`, OpenDrop
parle AirDrop par-dessus.

## Prérequis

```sh
# Dépendances de compilation d'OWL (Fedora)
sudo dnf install cmake libpcap-devel libev-devel libnl3-devel

# OWL, hors du dépôt
git clone --recursive https://github.com/seemoo-lab/owl.git ~/.local/src/owl
cmake -S ~/.local/src/owl -B ~/.local/src/owl/build -DCMAKE_POLICY_VERSION_MINIMUM=3.5
make -C ~/.local/src/owl/build owl

# OpenDrop, dans un venv à la racine du dépôt
python3 -m venv .venv
.venv/bin/pip install opendrop "setuptools<81"
```

`setuptools<81` est nécessaire : OpenDrop (dernière version de 2021) importe encore
`pkg_resources`, absent des environnements Python récents.

## Lancer

Depuis la racine du dépôt, iPhone réglé sur AirDrop « Tout le monde » :

```sh
sudo bash poc/airdrop-poc.sh find          # lister les appareils AirDrop à portée
sudo bash poc/airdrop-poc.sh receive       # être visible et recevoir des fichiers
sudo bash poc/airdrop-poc.sh send FICHIER  # chercher 30 s puis envoyer à l'appareil 0
```

Le Wi-Fi est coupé pendant l'essai et rétabli à la sortie (Ctrl+C). Journaux dans
`poc/out/`, fichiers reçus dans `poc/out/received/`.

Variables utiles : `IFACE` (défaut `wlp2s0`), `CHANNEL` (défaut 149), `DEVICE_NAME`,
`FIND_SECONDS`, `OWL_BIN`.

## Scripts de diagnostic

`diagnostics/` contient les scripts qui ont servi à caractériser la carte RTL8852BE
(injection, canaux, astuce du point d'accès). Ils sont conservés pour référence et
contiennent des chemins propres à la machine de développement.
