# Diagnostics USB — ce qu'on sait sur le matériel réel

Ce document consolide tout ce qui a été établi empiriquement sur la machine de l'utilisateur
concernant la topologie USB, l'alimentation et la détection de pannes. Objectif : ne plus jamais
reperdre ce travail, et ne pas relancer une recherche déjà faite. **Ce sujet est gelé** : sauf
demande explicite, ne pas modifier le code de détection USB au-delà de ce que ce document décrit.

## Topologie physique réelle du MacBook

Le MacBook a deux ports USB-C/Thunderbolt utilisés :

- **Port 1 — USB direct** : un hub GenesysLogic, avec deux disques Netac MobileDataStar
  bus-powered branchés dessus, chacun consommant environ 4.48 W :
  - "MUSIC 2To"
  - "SONS 1TO"
- **Port 2 — Thunderbolt** : un **Elgato Thunderbolt 3 Pro Dock**, qui héberge l'Apollo Solo
  (l'interface audio). Ce dock expose plusieurs contrôleurs USB internes distincts :
  - Fresco Logic FL1100
  - 2× ASMedia ASM1242
  Les trois sont bien identifiés comme faisant partie du même dock physique via leur **PCI
  Subsystem Vendor ID commun `0x1cfa`** (Elgato) — c'est la clé qui permet de les regrouper malgré
  des noms de puce différents.
  On trouve aussi sur cette branche des hubs Renesas/Terminus, un clavier Arturia, et un boîtier
  Orico multi-disques (voir plus bas, "BACK MUSIC 3TO").

**Non résolu, à ne pas réinventer** : l'utilisateur décrit un hub physique à 10 ports qui n'a
jamais pu être localisé, malgré une recherche exhaustive dans `system_profiler`, `ioreg` et via
libusb. Tous les hubs effectivement trouvés rapportent 4 ports. Ce hub à 10 ports reste une
inconnue — ne pas prétendre l'avoir identifié dans une future session sans nouvelle preuve.

## Comment cette topologie a été établie

Trois sources combinées, aucune suffisante seule :

1. **`system_profiler -json SPUSBHostDataType`** (et `SPThunderboltDataType`, `SPPCIDataType`) —
   donne l'arbre bus/hub/appareil avec noms, IDs vendeur/produit, et `USBDeviceKeyPowerAllocation`
   quand macOS le rapporte. C'est la seule source de wattage.
2. **`ioreg -p IOUSB -l -r -c IOUSBHostDevice`** — arbre plus détaillé, mais son indentation
   textuelle est piégeuse : un parsing naïf ligne-par-ligne donne un mauvais rattachement
   parent/enfant. Il faut suivre la profondeur d'indentation réelle (les `|`/espaces devant chaque
   ligne), pas juste l'ordre d'apparition, pour reconstruire l'arbre correctement.
3. **libusb** (`brew install libusb`) — utilisé pour lire `bNbrPorts` (nombre de ports physiques
   d'un hub) via une requête de descripteur de classe Hub brute :
   - type `0x29` pour un hub USB2
   - type `0x2A` pour un hub USB3/SuperSpeed (si `bcdUSB >= 0x0300`)
   C'est la seule des trois sources qui donne ce nombre de ports fiable — ni `system_profiler` ni
   `ioreg` ne l'exposent directement.

Le regroupement "ces 3 contrôleurs = 1 seul dock physique" vient de la comparaison du PCI Subsystem
Vendor ID (`0x1cfa` = Elgato) entre les entrées `SPPCIDataType`, pas d'un nom de produit commun.

## Wattage

Disponible **uniquement** via `system_profiler` (`USBDeviceKeyPowerAllocation` par appareil, quand
macOS le rapporte — pas systématique). Pas de mA/V en temps réel, pas de mesure de courant
instantanée. **Aucune mesure n'est possible en dehors du Mac** sans matériel externe (un wattmètre
USB en ligne). Ce que le Mac expose est un chiffre négocié/déclaré à l'enumération, pas une lecture
live d'un capteur.

## Détection de déconnexion USB

`Sources/StudioSwitchCore/Health/IOKitUSBPowerFaultDetector.swift` (créé et validé par la session
locale ; **absent de `main-zxu1x1` sur GitHub au moment d'écrire ce document** — voir la note en
fin de fichier) utilise :

- `IOServiceAddMatchingNotification` sur `IOUSBHostDevice` pour détecter l'apparition/disparition
  d'appareils.
- `IOServiceAddInterestNotification` pour recevoir les messages `kIOMessageDeviceWillPowerOff`
  (`0x210`) et `kIOMessageServiceIsTerminated` (`0x010`).

Validé en conditions réelles en débranchant/rebranchant un vrai disque : les deux messages sont
bien reçus au bon moment. **Fiable uniquement pour une déconnexion franche** (le disque disparaît
du bus) — ça ne détecte rien tant que l'appareil reste énuméré, même s'il est mal alimenté.

## Limite connue : "sous-alimenté mais toujours connecté"

Aucune mesure directe de courant n'existe sur cette machine (confirmé empiriquement : débrancher
l'alimentation secteur d'un hub self-powered ne change rien dans `system_profiler` ni `ioreg` tant
que le hub reste électriquement actif). Mais un vrai incident a été capturé dans le journal noyau
pour **"BACK MUSIC 3TO"** (le boîtier Orico) :

```
fConsecutiveResetCount = 1
I/O error! ... happened 2 times
status 0xe0005000 (pipe stalled)
```

C'est la **seule voie réaliste identifiée à ce jour** pour détecter un problème d'alimentation sans
coupure franche : des resets de pipe consécutifs et des erreurs I/O répétées sur un appareil qui
reste par ailleurs énuméré. **Non implémenté** — piste future si le besoin revient, mais ne pas la
construire sans une nouvelle demande explicite : la dernière tentative de détection heuristique par
journal (`log show` + mots-clés génériques, approche précédente) s'est révélée trop peu fiable pour
être livrée telle quelle.

## Nettoyage : fichiers morts, superseded par IOKitUSBPowerFaultDetector

Les fichiers suivants implémentaient l'approche précédente (lecture heuristique du journal système
via `log show`, avant qu'on ait la détection IOKit ci-dessus) et ne sont plus référencés nulle part
une fois `IOKitUSBPowerFaultDetector` en place :

- `Sources/StudioSwitchCore/Health/KernelLogUSBPowerFaultDetector.swift`
- `Sources/StudioSwitchCore/Health/LogShowUSBKernelLogInspector.swift`
- `Sources/StudioSwitchCore/Health/USBKernelLogInspecting.swift`
- leurs fichiers de test correspondants sous `Tests/StudioSwitchCoreTests/`

> **Non fait dans ce commit** : au moment d'écrire ce document, `IOKitUSBPowerFaultDetector.swift`
> n'existe pas encore sur la branche `main-zxu1x1` telle que visible depuis GitHub (dernier commit
> `7ffa8c3`) — seulement décrit comme "déjà commité" côté session locale, donc probablement pas
> encore poussé. Supprimer les fichiers ci-dessus maintenant casserait la compilation
> (`SystemHealthChecker` et `MenuBarView` en dépendent par défaut). À faire dès que
> `IOKitUSBPowerFaultDetector.swift` est effectivement présent sur cette branche : vérifier par
> `grep` que les fichiers ci-dessus ne sont plus référencés, les supprimer, puis `swift build &&
> swift test`.
