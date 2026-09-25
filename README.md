# FileTidy

Application macOS native (SwiftUI) qui range le **Bureau**, les **Téléchargements**,
ou tout autre dossier que vous ajoutez, en analysant uniquement leur contenu **à la racine**
(les sous-dossiers ne sont jamais explorés ni modifiés).

## Fonctionnalités

- **Rangement intelligent par type de fichier** : chaque fichier se voit proposer un
  déplacement vers un sous-dossier (`Images/`, `Documents/`, `Archives/`, `Installateurs/`,
  `Vidéos/`, `Audio/`, `Autres/`) créé dans le dossier surveillé lui-même.
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
`FileCategory.allCategories`.

## Architecture

```
Sources/FileTidy/
├── FileTidyApp.swift          # Point d'entrée SwiftUI
├── Models/                    # FileCategory, WatchedFolder, ScanItem, DuplicateGroup
├── Services/                  # Scan (FolderScanner), règles de nettoyage (CleanupAdvisor),
│                               # détection de doublons (DuplicateFinder), actions fichiers
│                               # (FileOperationService : déplacer / mettre à la corbeille)
├── ViewModels/                # OrganizerViewModel : orchestre scan + actions
├── Views/                     # Barre latérale, listes à cocher, écran principal
└── Support/                   # Utilitaires (formatage des tailles de fichiers)
```

## Limites connues (v1)

- La détection "archive déjà décompressée" est heuristique (nom de fichier/dossier
  identique à côté du `.zip`), pas une vérification du contenu de l'archive.
- Le tri ne prend en compte que le premier niveau du dossier surveillé (comportement
  voulu, pour ne jamais toucher à une arborescence déjà organisée).
- Pas encore d'interface pour personnaliser les catégories sans modifier le code.
