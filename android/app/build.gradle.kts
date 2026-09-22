import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (docs/RELEASING.md). `android/key.properties` is never committed: the
// release workflow writes it from repository secrets, and a maintainer can create one to
// sign locally. Without it a release build falls back to the debug key so that
// `flutter run --release` keeps working — an APK signed that way must never be published:
// Android refuses to update an app whose signing certificate changed.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    // A present but incomplete file must not fall through to the debug key, nor hand
    // Gradle a null: name what is missing and stop.
    val missing = listOf("storeFile", "storePassword", "keyPassword", "keyAlias")
        .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    check(missing.isEmpty()) {
        "android/key.properties is missing: ${missing.joinToString()} (docs/RELEASING.md)"
    }
}

android {
    namespace = "foundation.mostro.app"
    compileSdk = flutter.compileSdkVersion
    // Pin NDK version for reproducible Rust cross-compilation builds
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "foundation.mostro.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // mobile_scanner requires 21+; flutter_secure_storage requires 18+
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // `flutter build apk --split-per-abi` (the release workflow) configures `splits.abi`
        // from --target-platform, and AGP rejects ndk.abiFilters next to it ("Conflicting
        // configuration"). The filter is only needed for a fat APK.
        if (project.findProperty("split-per-abi")?.toString() != "true") {
            ndk {
                // ABI targets for flutter_rust_bridge Rust cross-compilation
                abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
            }
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKeystore) "release" else "debug"
            )
        }
    }

    packaging {
        jniLibs {
            // Preserve 16 KB page alignment in packaged .so files (Android 15+ requirement)
            useLegacyPackaging = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
