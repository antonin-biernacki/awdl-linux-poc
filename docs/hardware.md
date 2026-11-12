# Compatibilité matérielle

poc s'appuie sur [OWL](https://github.com/seemoo-lab/owl) pour parler AWDL, le
protocole Wi-Fi d'AirDrop. OWL demande beaucoup plus à la carte Wi-Fi qu'une connexion
classique :

- le **mode moniteur**, pour recevoir toutes les trames du canal ;
- l'**injection de trames**, pour émettre des trames AWDL ;
- idéalement le **mode moniteur actif**, où la carte acquitte (ACK) les trames qui lui
  sont destinées. Sans lui, l'émetteur retransmet chaque trame jusqu'à 7 fois et le
  débit chute ;
- la réception sur un **canal AWDL** : 6 (2,4 GHz), 44 ou 149 (5 GHz).

## Vérifier sa carte

```sh
# Modes pris en charge : "monitor" doit apparaître
iw list | grep -A10 "Supported interface modes"

# Mode moniteur actif : la ligne doit apparaître
iw phy phy0 info | grep -i "active monitor"

# Canaux autorisés : 6, 44 et 149 ne doivent pas être "disabled" ni "no IR"
iw list | grep -E "\[(6|44|149)\]"
```

L'injection se teste avec `aireplay-ng --test <interface>` (paquet `aircrack-ng`), carte
en mode moniteur sur un canal où des points d'accès sont à portée.

## Cartes testées

| Carte | Pilote | Résultat |
|-------|--------|----------|
| Realtek RTL8852BE (PCIe, 802.11ax) | `rtw89_8852be` | Fonctionne, avec deux contournements (voir ci-dessous) |

### Realtek RTL8852BE

Testée sous Fedora 44, noyau 7.2.15, firmware 0.29.29.18 (`linux-firmware-20261019`).

| Fonction | État |
|----------|------|
| Mode moniteur | Oui |
| Mode moniteur actif | **Non** : `ACTIVE_MONITOR` absent, OWL échoue avec `Operation not supported` |
| Injection de trames | Oui, testée sur le canal 157 |
| Réception en mode moniteur | **Seulement sur le dernier canal où le firmware a opéré** (voir ci-dessous) |
| Découverte AWDL avec OWL | Oui, avec les deux contournements |

**Réception limitée à un canal.** Après le passage en mode moniteur, `iw` accepte le
changement de canal et la radio quitte bien l'ancien canal, mais elle ne reçoit plus
(presque) rien sur le nouveau. Elle ne reçoit normalement que sur le canal où la carte
était associée juste avant. Couper puis relancer l'interface n'y change rien.

**Contournements :**

1. *Pas de mode moniteur actif* : passer soi-même la carte en mode moniteur simple, puis
   lancer OWL avec `-N` pour qu'il ne touche pas à la configuration :
   ```sh
   ip link set wlp2s0 down
   iw dev wlp2s0 set type monitor
   ip link set wlp2s0 up
   owl -i wlp2s0 -c 149 -N
   ```
2. *Réception limitée à un canal* : faire d'abord opérer le firmware sur le canal AWDL voulu
   en lançant un point d'accès éphémère, puis passer en mode moniteur sur ce même canal :
   ```sh
   nmcli device wifi hotspot ifname wlp2s0 band a channel 149 ssid poc-tmp password <mdp>
   nmcli connection down Hotspot
   nmcli device set wlp2s0 managed no
   # puis le contournement 1, et : iw dev wlp2s0 set channel 149
   ```

Conséquences :

- OWL doit rester sur un seul canal (c'est son comportement par défaut) ;
- sans mode moniteur actif, il faut s'attendre à un débit de transfert dégradé ;
- ce comportement du firmware n'est pas documenté et peut changer avec une mise à jour.

## Cartes recommandées

Pour un fonctionnement sans contournement, il faut une carte qui gère le mode moniteur
actif. Les équipes d'OWL ont développé avec une **Atheros AR9280** (pilote `ath9k`). Côté
clés USB, les puces **MediaTek MT7612U** (pilote `mt76`, 2,4 et 5 GHz) sont réputées
compatibles mais n'ont pas encore été testées pour ce projet.

Les résultats sur d'autres cartes sont les bienvenus : ajoutez une ligne au tableau
« Cartes testées » avec le pilote, la version du noyau et ce qui fonctionne.
