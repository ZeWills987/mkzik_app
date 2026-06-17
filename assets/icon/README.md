# Icône d'application

Place ici l'icône source de l'app sous le nom **`icon.png`**.

Contraintes :
- **PNG carré 1024 × 1024 px**
- **Sans transparence** (fond plein) — iOS rejette les icônes avec canal alpha
- Évite le texte trop petit (l'icône est affichée en petit)

Puis génère les icônes iOS + Android :

```bash
flutter pub get
flutter pub run flutter_launcher_icons
```

La configuration se trouve dans `pubspec.yaml`, section `flutter_launcher_icons`.
