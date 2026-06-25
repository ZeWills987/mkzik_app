# Mkzik

Application mobile de streaming musical avec une identité visuelle polynésienne
(motifs Patutiki marquisiens). Client Flutter pour l'API Mkzik (backend Symfony +
service de recherche Python).

## Fonctionnalités

- Lecture audio en arrière-plan (contrôles écran verrouillé / notification)
- Recherche de titres et d'utilisateurs, tri par pertinence / date
- Profils, abonnements (follow), favoris (like)
- Fil « Dernière sortie » et historique d'écoute paginés
- Bibliothèque des titres likés

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

## Build & distribution

Les builds sont automatisés via GitHub Actions :

- **iOS** — commit contenant `[ios]` ou `[build]` → IPA non signé publié sur la
  release `ios-latest`, distribué via SideStore ([page d'install](index.html)).
- **Android** — commit contenant `[android]` ou `[build]` → APK publié sur la
  release `android-latest`.

Le `.env` de production est injecté en CI depuis le secret `MOBILE_ENV_FILE`.