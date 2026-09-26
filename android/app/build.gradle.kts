import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// FCM wake-ups are optional: they are enabled when the Firebase project's
// google-services.json is placed next to this file. Without it the app falls back to
// periodic sync (and live updates while it's open).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Release signing: from environment variables (CI) or android/key.properties (local, git-ignored):
//   VIA_KEYSTORE_FILE / storeFile, VIA_KEYSTORE_PASSWORD / storePassword,
//   VIA_KEY_ALIAS / keyAlias, VIA_KEY_PASSWORD / keyPassword
// Without them, release builds are signed with the debug key (fine for local testing only).
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
fun signingValue(env: String, property: String): String? =
    System.getenv(env)?.takeIf { it.isNotEmpty() } ?: keyProperties.getProperty(property)
val releaseStoreFile = signingValue("VIA_KEYSTORE_FILE", "storeFile")

android {
    namespace = "com.kamofa.via"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.kamofa.via"
        // 29: saving to Downloads through MediaStore without storage permissions.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile)
                storePassword = signingValue("VIA_KEYSTORE_PASSWORD", "storePassword")
                keyAlias = signingValue("VIA_KEY_ALIAS", "keyAlias")
                keyPassword = signingValue("VIA_KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation(platform("com.google.firebase:firebase-bom:34.3.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("androidx.work:work-runtime-ktx:2.10.3")
}
