import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Auto-incrément du versionCode à chaque build ────────────────────────────
// Un compteur persistant (android/app/version.properties, gitignoré) monte de 1
// à chaque build Android. versionName reste piloté par pubspec (version: x.y.z).
val buildCounterFile = file("version.properties")
val buildProps = Properties().apply {
    if (buildCounterFile.exists()) buildCounterFile.inputStream().use { load(it) }
}
val autoVersionCode = maxOf(
    (buildProps.getProperty("buildCode")?.toIntOrNull() ?: 0) + 1,
    flutter.versionCode,
)
buildProps.setProperty("buildCode", autoVersionCode.toString())
buildCounterFile.outputStream().use { buildProps.store(it, "Auto-incrément à chaque build — ne pas éditer à la main") }

android {
    namespace = "fr.mkzik.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "fr.mkzik.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 23 requis par flutter_secure_storage (encryptedSharedPreferences
        // → androidx.security.crypto, API 23+). Couvre >99 % du parc Android.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        // Play Store exige targetSdk >= 35 (Android 15) pour les nouvelles apps
        // et les mises à jour depuis fin août 2025.
        targetSdk = 35
        versionCode = autoVersionCode // auto-incrémenté à chaque build (cf. ci-dessus)
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
