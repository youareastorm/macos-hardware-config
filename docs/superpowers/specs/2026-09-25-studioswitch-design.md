# StudioSwitch — design

Date : 2026-09-25

## Contexte et objectif

Simon possède deux configurations home-studio :
- **Home** : interface audio Universal Audio **Apollo Solo**
- **Studio** : interface audio Universal Audio **Apollo** (rack)

Il utilise aussi 2 interfaces Focusrite, hors périmètre de cette v1.

À chaque changement de lieu, il doit aujourd'hui manuellement :
1. Choisir la bonne session UAD Console pour l'interface branchée
2. Vérifier/régler le device audio par défaut du système
3. Lancer le bon DAW (Logic Pro, Ableton Live, Pro Tools, Cubase ou Bitwig Studio)

**Objectif** : une app macOS de barre de menu avec deux boutons ("Home" / "Studio") qui automatise les étapes 1 et 2, puis propose de lancer un des 5 DAW.

## Périmètre de la v1

Inclus :
- Détection de l'interface Apollo connectée (CoreAudio)
- Réglage du device audio par défaut du système (input + output) sur cette interface
- Activation de l'IAC Driver MIDI si celui-ci est configuré comme utilisé (voir section MIDI)
- Chargement automatique de la session UAD Console (`.uadmix`) correspondante
- Sélecteur pour lancer un des 5 DAW installés, avec ouverture d'un template de projet optionnel

Explicitement hors périmètre v1 (améliorations futures, une fois validées une par une) :
- Support des interfaces Focusrite
- Forcer le device audio *à l'intérieur* de chaque DAW (voir "Risques et décisions" ci-dessous)
- Édition fine de la fenêtre "MIDI Studio" d'Audio MIDI Setup (pas d'API publique documentée pour ça)

## Faits vérifiés sur la machine de Simon (2026-09-25)

- UAD Console (`/Applications/Universal Audio/UAD Console.app`) enregistre `application:openFile:` / `application:openFiles:` — pas de dictionnaire AppleScript, mais l'ouverture de fichier standard fonctionne. Les sessions existantes (`.uadmix`) sont dans `~/Documents/Universal Audio/Sessions/` (ex. `home guit vox.uadmix`, `octo.uadmix`, `REC VOX OCTO.uadmix`).
- Les 5 DAW cibles sont installés : Logic Pro, Ableton Live 12 (Standard + Suite), Pro Tools, Cubase 13/14/15, Bitwig Studio.
- Chaque DAW stocke son device audio sélectionné dans un format propriétaire non documenté :
  - Ableton : `~/Library/Preferences/Ableton/Live 12.x/Preferences.cfg` → format binaire opaque (`file` le rapporte comme "data")
  - Logic Pro : `~/Library/Preferences/com.apple.logic10.plist` → plist binaire, clés non documentées
  - Pro Tools : `~/Library/Preferences/com.avid.ProTools.plist` → idem
  - Cubase : `~/Library/Preferences/com.steinberg.cubase1{3,4,5}.plist` → idem
  - Bitwig : `~/Library/Preferences/com.bitwig.studio.plist` + dossier `~/Library/Application Support/Bitwig`

## Risques et décisions

**Décision** : on ne tente pas d'éditer ces fichiers de préférence pour forcer le device dans chaque DAW en v1 — format non documenté, binaire, risque de corruption, et à refaire à chaque mise à jour (3 versions de Cubase et 2 d'Ableton déjà installées en parallèle). À la place, la v1 règle le device par défaut du système ; beaucoup de configurations "Core Audio / device système" dans les DAW suivront ce changement automatiquement. Le pinning explicite dans un DAW donné sera traité comme une amélioration ultérieure, DAW par DAW, uniquement si on constate qu'il ne suit pas le device système — probablement via UI-scripting AppleScript/System Events à ce moment-là (nécessite la permission Accessibilité).

**Décision** : pas d'édition programmatique de la fenêtre "MIDI Studio" (pas d'API publique). On se limite à activer l'IAC Driver via ses préférences si Simon l'utilise (voir composant `MIDIConfigurator`).

## Architecture

Projet Xcode (app SwiftUI macOS, non sandboxée — elle a besoin d'ouvrir des fichiers arbitraires et de lancer d'autres applications). App de barre de menu (`LSUIElement`, pas d'icône dans le Dock, pas de fenêtre principale).

### Composants

- **`AudioInterfaceDetector`** : énumère les devices CoreAudio (`kAudioHardwarePropertyDevices`), lit nom/fabricant, et détermine si le device attendu par un profil (ex. "Apollo Solo") est actuellement branché.
- **`Profile` / `ProfileStore`** : modèle de profil (nom, motif de nom de device attendu, chemin du fichier `.uadmix`, liste des DAW disponibles avec chemin de template optionnel). Chargé depuis un fichier JSON éditable à la main : `~/Library/Application Support/StudioSwitch/profiles.json`. Deux profils par défaut : "Home" (Apollo Solo) et "Studio" (Apollo).
- **`UADConsoleController`** : ouvre le fichier `.uadmix` du profil via `NSWorkspace.shared.open(urls:withApplicationAt:configuration:)` en ciblant `UAD Console.app`.
- **`AudioMIDIConfigurator`** : règle le device par défaut système (`kAudioHardwarePropertyDefaultInputDevice` / `DefaultOutputDevice` / `DefaultSystemOutputDevice`) sur l'interface détectée. Active l'IAC Driver si configuré comme utilisé dans le profil.
- **`DAWLauncher`** : lance l'app DAW choisie (`NSWorkspace.shared.openApplication`), en ouvrant le template associé si présent dans le profil.
- **`MenuBarView`** (SwiftUI) : icône de barre de menu, menu avec les boutons "Home" / "Studio", puis un sélecteur des DAW disponibles pour le profil une fois l'étape précédente terminée.

### Flux (cas nominal)

1. Simon clique sur "Home" (ou "Studio") dans le menu.
2. `AudioInterfaceDetector` vérifie que l'interface attendue par ce profil est branchée.
   - Si absente : alerte ("Apollo Solo non détecté"), on s'arrête là.
3. `AudioMIDIConfigurator` règle le device par défaut du système sur cette interface, et active l'IAC Driver si demandé par le profil.
4. `UADConsoleController` ouvre la session `.uadmix` du profil dans UAD Console.
5. Le menu affiche les 5 DAW ; Simon clique sur celui qu'il veut.
6. `DAWLauncher` lance ce DAW (et ouvre son template si un chemin est configuré pour ce DAW dans ce profil).

### Gestion des erreurs

- Interface attendue non détectée → alerte bloquante, aucune action suivante n'est effectuée.
- Fichier `.uadmix` introuvable ou UAD Console non installé → alerte, on continue quand même vers l'étape device système / DAW.
- Échec de réglage du device par défaut (device occupé, permission) → alerte avec le message système, on continue vers UAD Console / DAW.
- DAW ou template introuvable → alerte ; si seul le template manque, le DAW est lancé sans lui.

Chaque étape est indépendante : l'échec d'une étape n'empêche pas de tenter les suivantes (sauf l'étape 2, qui bloque tout si l'interface n'est pas détectée).

### Tests

- Tests unitaires pour la logique de correspondance profil ↔ device (avec une liste de devices simulée) et le chargement/parsing du JSON de config.
- Les appels CoreAudio réels (réglage du device par défaut, énumération matérielle) et le lancement d'UAD Console / DAW ne sont pas testables unitairement sans le matériel — vérification manuelle via une checklist dans le plan d'implémentation.

## Configuration (exemple `profiles.json`)

```json
{
  "profiles": [
    {
      "name": "Home",
      "deviceNameMatch": "Apollo Solo",
      "uadConsoleSession": "~/Documents/Universal Audio/Sessions/home guit vox.uadmix",
      "useIACDriver": false,
      "daws": [
        { "name": "Logic Pro", "bundleId": "com.apple.logic10", "template": null },
        { "name": "Ableton Live 12 Suite", "bundleId": "com.ableton.live", "template": null }
      ]
    },
    {
      "name": "Studio",
      "deviceNameMatch": "Apollo",
      "uadConsoleSession": "~/Documents/Universal Audio/Sessions/octo.uadmix",
      "useIACDriver": false,
      "daws": [
        { "name": "Pro Tools", "bundleId": "com.avid.ProTools", "template": null },
        { "name": "Cubase 15", "bundleId": "com.steinberg.cubase15", "template": null }
      ]
    }
  ]
}
```

Ce fichier est un point de départ éditable à la main ; les chemins de session/templates exacts seront ajustés par Simon après la première installation.
