# Mkzik

Application de streaming musical avec une identité visuelle polynésienne
(motifs Patutiki marquisiens). Client Flutter pour l'API Mkzik (backend Symfony +
service de recherche Python).

**Plateformes :** Android · iOS · **Windows (desktop)**

## Fonctionnalités

- Lecture audio en arrière-plan (contrôles écran verrouillé / notification mobile,
  contrôles média système SMTC sur Windows)
- Recherche de titres et d'utilisateurs, tri par pertinence / date
- Profils, abonnements (follow), favoris (like)
- Fil « Dernière sortie » et historique d'écoute paginés
- Bibliothèque des titres likés
- Paroles synchronisées + plein écran (disposition deux colonnes sur desktop)

## Version desktop (Windows)

L'app tourne nativement sur Windows avec une interface adaptée :

- Barre latérale de navigation (au lieu de la barre du bas mobile)
- Feuilles d'actions en dialogs centrés
- Contrôles de lecture étendus dans le mini-lecteur
- Contrôles média système Windows (touches média + panneau média) via `smtc_windows`
- Raccourci **Échap** pour fermer le lecteur

Toute la logique desktop est conditionnée par la largeur d'écran ou la plateforme :
**aucun impact sur le rendu mobile**.

### Prérequis build Windows

- [Visual Studio](https://visualstudio.microsoft.com/) avec la charge
  **« Développement Desktop en C++ »**
- [Rust](https://rustup.rs/) (`cargo` sur le PATH) — requis par `smtc_windows`

```bash
flutter config --enable-windows-desktop
flutter run -d windows
```

## Configuration

Les URLs de l'API sont lues depuis un fichier `.env` à la racine
(voir [`.env.example`](.env.example)) :

```env
API_URL=https://api.exemple.com/      # backend Symfony
PYTHON_URL=https://search.exemple.com/ # service de recherche
```

Sans `.env`, l'app retombe sur les valeurs de dev (émulateur Android `10.0.2.2`).

## Lancer en local

```bash
flutter pub get
flutter run
```


## Icône d'application

Place une icône `assets/icon/icon.png` (PNG carré 1024×1024, sans transparence)
puis génère les variantes iOS/Android :

```bash
flutter pub run flutter_launcher_icons
```

Pour l'icône Windows (générée séparément pour ne pas régénérer le mobile) :

```bash
flutter pub run flutter_launcher_icons -f flutter_launcher_icons_windows.yaml
```

## Build & distribution

Les builds sont automatisés via GitHub Actions. Un build se déclenche quand le
message de commit sur `main` contient le tag correspondant (ou `[build]` pour
tout builder), ou via « Run workflow » manuel :

- **iOS** — `[ios]` ou `[build]` → IPA non signé publié sur la release
  `ios-latest`, distribué via SideStore ([page d'install](index.html)).
- **Android** — `[android]` ou `[build]` → APK publié sur la release
  `android-latest`.
- **Windows** — `[windows]` ou `[build]` → ZIP (exe + DLL) publié sur la release
  `windows-latest`. Décompresser et lancer `mkzik_app.exe`.

Le `.env` de production est injecté en CI depuis le secret `MOBILE_ENV_FILE`.

Build