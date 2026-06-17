# Guide de publication — Mkzik

Préparation complète pour publier sur **Google Play** et l'**App Store**.
La configuration technique est déjà en place ; il te reste à créer les comptes,
générer les clés/certificats, et renseigner les secrets GitHub.

> Identifiant unique de l'app : **`fr.mkzik.app`** (Android + iOS).

---

## 1. Android — Google Play

### Prérequis
- Compte **Google Play Console** : 25 $ (paiement unique).
- Un **keystore** de signature (clé privée de l'app — à conserver précieusement,
  sa perte rend toute mise à jour future impossible).

### a) Générer le keystore (une seule fois)
```bash
keytool -genkey -v -keystore mkzik-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias mkzik
```
Place `mkzik-release.jks` dans `android/app/`.

### b) Configurer la signature locale
Copie le modèle et renseigne tes mots de passe :
```bash
cp android/key.properties.example android/key.properties
```
`key.properties` et `*.jks` sont **gitignorés** — ils ne partent jamais sur GitHub.

### c) Builder l'App Bundle (format exigé par Play)
```bash
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```
Le build est automatiquement signé si `android/key.properties` existe.

### d) Build signé en CI (optionnel)
Workflow [`android-release.yml`](.github/workflows/android-release.yml) — commit
contenant `[play]` ou lancement manuel. Secrets GitHub à créer :

| Secret | Contenu |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 mkzik-release.jks` |
| `ANDROID_STORE_PASSWORD` | mot de passe du keystore |
| `ANDROID_KEY_PASSWORD` | mot de passe de la clé |
| `ANDROID_KEY_ALIAS` | `mkzik` |

L'`.aab` signé est récupérable dans les artifacts du workflow.

---

## 2. iOS — App Store

### Prérequis
- Compte **Apple Developer Program** : 99 $/an (pas de paiement mensuel).
- Un **certificat de distribution** + un **provisioning profile** App Store
  pour `fr.mkzik.app` (créés depuis developer.apple.com ou Xcode).

### a) Renseigner le Team ID
Dans [`ios/ExportOptions.plist`](ios/ExportOptions.plist), remplace
`TEAM_ID_A_REMPLIR` par ton Team ID (App Store Connect → Membership).

### b) Build local (avec un Mac + Xcode)
```bash
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
# → build/ios/ipa/*.ipa  → à téléverser via Xcode ou Transporter
```

### c) Build signé en CI (sans Mac)
Workflow [`ios-release.yml`](.github/workflows/ios-release.yml) — commit
contenant `[appstore]` ou lancement manuel. Secrets GitHub à créer :

| Secret | Contenu |
|---|---|
| `IOS_DIST_CERT_P12_BASE64` | certificat `.p12` exporté en base64 |
| `IOS_DIST_CERT_PASSWORD` | mot de passe du `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | profil `.mobileprovision` en base64 |

---

## 3. Checklist de conformité (déjà fait ✅ / à fournir ⏳)

### Technique (fait)
- ✅ Identifiant `fr.mkzik.app` unifié
- ✅ Nom d'app « Mkzik »
- ✅ iOS : cible minimale iOS 15, ATS HTTPS strict, flag de chiffrement export
- ✅ Android : `targetSdk 35`, cleartext interdit en release
- ✅ Signature : config Gradle + scaffolding iOS prêts

### À fournir côté stores (⏳ toi)
- ⏳ **Icône** : `assets/icon/icon.png` (1024×1024, sans alpha) puis
  `flutter pub run flutter_launcher_icons`
- ⏳ **Politique de confidentialité** (URL publique) — **obligatoire** sur les
  deux stores (l'app accède au réseau, aux photos, aux comptes utilisateurs)
- ⏳ **Captures d'écran** : Play (téléphone min. 2) ; App Store (6,7" et 5,5")
- ⏳ **Play** : formulaire *Data Safety* + classification de contenu +
  déclaration d'usage du *foreground service media playback*
- ⏳ **App Store** : *App Privacy* (nutrition labels) + description + mots-clés
- ⏳ **Versioning** : incrémenter `version:` dans `pubspec.yaml` à chaque envoi

---

## 4. Rappel des canaux de distribution

| Canal | Build | Workflow | Déclencheur |
|---|---|---|---|
| Sideload iOS (SideStore) | IPA non signé | `ios.yml` | `[ios]` / `[build]` |
| APK direct Android | APK | `android.yml` | `[android]` / `[build]` |
| **Play Store** | **AAB signé** | `android-release.yml` | `[play]` |
| **App Store** | **IPA signé** | `ios-release.yml` | `[appstore]` |
