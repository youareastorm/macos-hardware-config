# FileTidy

Application macOS native (SwiftUI) qui range le **Bureau**, les **Téléchargements**,
ou tout autre dossier que vous ajoutez, en analysant uniquement leur contenu **à la racine**
(les sous-dossiers ne sont jamais explorés ni modifiés).

## Fonctionnalités

- **Rangement intelligent**, dans cet ordre de priorité pour chaque fichier :
  1. **Dossier existant** : si le nom du fichier partage un mot significatif avec un
     dossier déjà présent (à la racine, ou déjà rangé dans une catégorie —
     ex. `Documents/Factures`), FileTidy propose de l'y ranger plutôt que dans la
     catégorie générique.
  2. **Nouveau dossier proposé** : si plusieurs fichiers restants partagent un nom
     proche (ex. `rapport-final-v1.pdf` et `rapport-final-v2.pdf`), FileTidy propose
     de créer un dossier dédié (`Documents/Rapport final/`) plutôt que de les laisser
     en vrac dans la catégorie.
  3. **Catégorie par défaut** : sinon, rangement classique par type de fichier
     (`Images/`, `Documents/`, `Archives/`, `Installateurs/`, `Vidéos/`, `Audio/`, `Autres/`).

  Cette analyse ne repose que sur les noms de fichiers/dossiers (aucune lecture de
  contenu), ce qui la garde quasi gratuite en CPU. Chaque proposition indique
  clairement pourquoi elle a été faite (dossier existant vs. nouveau dossier).
- **Détection des fichiers indésirables** :
  - fichiers `.torrent` (métadonnées de téléchargement, inutiles une fois le
    téléchargement terminé) ;
  - archives `.zip` déjà décompressées (un fichier/dossier du même nom existe déjà à côté).
- **Détection des doublons** : comparaison par empreinte SHA-256 (et non juste par nom),
  la copie la plus ancienne est gardée par défaut, les autres proposées à la suppression.
- **Tout se fait par cases à cocher** : rien n'est déplacé ou supprimé sans que vous
  cochiez explicitement l'action, puis cliquiez sur *Appliquer les actions sélectionnées*.
- **Suppression = corbeille**, jamais définitive : toute suppression passe par
  `FileManager.trashItem`, donc toujours récupérable depuis la Corbeille macOS.
- **Dossiers personnalisés** : en plus du Bureau et des Téléchargements (ajoutés
  automatiquement), vous pouvez ajouter n'importe quel autre dossier via le bouton `+`
  dans la barre latérale.

## Lancer le projet

Ce dépôt est un package Swift (pas besoin de `.xcodeproj`) :

1. Ouvrez `Package.swift` avec Xcode (double-clic, ou `open Package.swift`).
2. Choisissez le schéma **FileTidy** et la destination **My Mac**.
3. Lancez avec ▶️ (Cmd+R).

Ou en ligne de commande (macOS uniquement, Swift 5.9+) :

```bash
swift run
```

Prérequis : macOS 13 (Ventura) ou plus récent, Xcode 15 ou plus récent.

## Permissions macOS

L'application n'est **pas sandboxée** : à la première analyse d'un dossier protégé
(Bureau, Téléchargements), macOS affichera une demande d'autorisation système standard
("FileTidy souhaite accéder aux fichiers de..."). Il suffit d'autoriser pour que
l'analyse fonctionne. Pour les dossiers personnalisés ajoutés via le bouton `+`,
aucune autorisation supplémentaire n'est nécessaire.

## Personnaliser les règles de tri

Les catégories et leurs extensions associées sont définies dans
[`Sources/FileTidy/Models/FileCategory.swift`](Sources/FileTidy/Models/FileCategory.swift) :
il suffit d'ajouter une extension à un ensemble existant, ou une nouvelle
`FileCategory` (avec son nom de dossier et ses extensions), puis de l'ajouter à
`FileCategory.allCategories`. La logique de correspondance par nom (dossiers
existants / regroupement) est dans
[`Sources/FileTidy/Services/SmartOrganizer.swift`](Sources/FileTidy/Services/SmartOrganizer.swift).

## Architecture

```
Sources/FileTidy/
├── FileTidyApp.swift          # Point d'entrée SwiftUI
├── Models/                    # FileCategory, MoveDestination, WatchedFolder, ScanItem, DuplicateGroup
├── Services/                  # Scan (FolderScanner), indexation des dossiers existants
│                               # (FolderIndexer), rangement intelligent par nom (SmartOrganizer),
│                               # règles de nettoyage (CleanupAdvisor), détection de doublons
│                               # (DuplicateFinder), actions fichiers (FileOperationService :
│                               # déplacer / mettre à la corbeille)
├── ViewModels/                # OrganizerViewModel : orchestre scan + actions
├── Views/                     # Barre latérale, listes à cocher, écran principal
└── Support/                   # Utilitaires (formatage des tailles de fichiers)
```

## Pourquoi une analyse à la demande (et pas une surveillance en continu) ?

Les meilleurs outils du genre (Hazel en tête) restent légers en réagissant aux
événements du système de fichiers plutôt qu'en scannant le disque en boucle.
FileTidy va plus loin sur ce point : il n'y a **aucun processus en arrière-plan** —
l'analyse ne s'exécute que lorsque vous cliquez sur *Analyser* ou changez de dossier,
donc une consommation CPU nulle au repos. Le calcul lui-même reste bon marché :
un seul niveau de dossier est lu (jamais de récursion), le hachage SHA-256 des
doublons ne s'exécute que sur des fichiers de même taille, et le rangement
intelligent ne fait que comparer des noms (aucune lecture de contenu).

## Limites connues (v1)

- La détection "archive déjà décompressée" est heuristique (nom de fichier/dossier
  identique à côté du `.zip`), pas une vérification du contenu de l'archive.
- Le tri ne prend en compte que le premier niveau du dossier surveillé (comportement
  voulu, pour ne jamais toucher à une arborescence déjà organisée) ; l'indexation des
  dossiers existants regarde un niveau de plus en lecture seule, uniquement pour
  proposer de meilleures destinations.
- Le rapprochement par nom est un heuristique simple (mots partagés, sans accents/pluriel) :
  volontairement transparent et sans réseau ni IA embarquée, donc parfois moins
  "malin" qu'un outil basé sur le contenu — mais prévisible et rapide.
- Pas encore d'interface pour personnaliser les catégories sans modifier le code.
