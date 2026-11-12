# poc

Envoyer et recevoir des fichiers en AirDrop depuis Linux, directement depuis les
réglages rapides (Quick Settings) de GNOME.

> **Statut : en développement.** Rien n'est encore utilisable.

## Principe

AirDrop repose sur AWDL (Apple Wireless Direct Link), un protocole Wi-Fi propriétaire
d'Apple, associé à une annonce en Bluetooth Low Energy. poc s'appuie sur les
travaux du projet [Open Wireless Link](https://owlink.org/) (Secure Mobile Networking
Lab, TU Darmstadt) :

- [OWL](https://github.com/seemoo-lab/owl) fournit l'interface réseau AWDL ;
- [OpenDrop](https://github.com/seemoo-lab/opendrop) implémente le protocole AirDrop
  par-dessus.

Le projet se compose de deux parties :

| Composant | Rôle | Technologie |
|-----------|------|-------------|
| `daemon/` | Découverte des appareils, envoi et réception des fichiers. Expose une API D-Bus. | Python, service utilisateur systemd |
| `extension/` | Bouton dans les Quick Settings, liste des appareils, notifications. Ne fait que de l'interface. | GJS (modules ESM), GNOME Shell 46+ |

Le travail réseau tourne dans le daemon et non dans l'extension : un blocage ou un
plantage côté réseau ne doit jamais figer GNOME Shell.

## Limites connues

- **Matériel** : AWDL exige une carte Wi-Fi qui accepte le mode moniteur **et**
  l'injection de trames. Beaucoup de cartes intégrées ne le permettent pas. Voir
  [docs/hardware.md](docs/hardware.md) pour vérifier sa carte et la liste des cartes testées.
- **Visibilité côté Apple** : sans certificat signé par Apple, un Mac ou un iPhone ne
  voit poc que s'il est réglé sur « Tout le monde ».
- **Wi-Fi** : pendant un transfert, la carte est dédiée à AWDL. Selon le matériel, la
  connexion Wi-Fi habituelle peut être coupée.
- Apple peut modifier AirDrop à chaque mise à jour, ce qui peut casser la compatibilité.

## Arborescence prévue

```
poc/
├── daemon/        # Service Python (paquet poc, tests)
├── extension/     # Extension GNOME Shell
├── data/          # Fichiers systemd et D-Bus
└── docs/          # Documentation technique
```

## Installation

À venir.

## Licence

[GPL-3.0-or-later](LICENSE). Cette licence est imposée par OpenDrop, lui-même sous
GPL-3.0.
