import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// -----------------------------------------------------------------------------
// Application identity
// -----------------------------------------------------------------------------
// Kept stable for every build type so an installed copy can be updated in place
// (as long as it was signed with the same key). Changing it creates a new app.
val zadApplicationId = "dev.zadalruh.zad_alruh"

// -----------------------------------------------------------------------------
// Release signing
// -----------------------------------------------------------------------------
// Priority:
//   1. android/key.properties (local machine; never committed)
//   2. Environment variables (CI): ZAD_KEYSTORE_PATH, ZAD_KEYSTORE_PASSWORD,
//      ZAD_KEY_ALIAS, ZAD_KEY_PASSWORD
//   3. Fallback: the Android debug key. The APK installs fine for sideloading,
//      but a later build signed with a different key cannot update it in place.
// See docs/ANDROID-SIGNING.ar.md.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(propertyKey: String, envKey: String): String? {
    val fromFile = keyProperties.getProperty(propertyKey)
    if (!fromFile.isNullOrBlank()) return fromFile
    val fromEnv = System.getenv(envKey)
    return if (fromEnv.isNullOrBlank()) null else fromEnv
}

val releaseStorePath: String? = signingValue("storeFile", "ZAD_KEYSTORE_PATH")?.trim()
val releaseStorePassword: String? = signingValue("storePassword", "ZAD_KEYSTORE_PASSWORD")
val releaseKeyAlias: String? = signingValue("keyAlias", "ZAD_KEY_ALIAS")
val releaseKeyPassword: String? = signingValue("keyPassword", "ZAD_KEY_PASSWORD")

val releaseStoreFile: File? = releaseStorePath?.let { path ->
    val raw = File(path)
    if (raw.isAbsolute) raw else rootProject.file(path)
}

val hasReleaseSigning = releaseStoreFile != null &&
    releaseStoreFile.isFile &&
    !releaseStorePassword.isNullOrBlank() &&
    !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank()

if (!hasReleaseSigning) {
    logger.warn(
        "Zad Al-Ruh: no release keystore configured; release builds will be signed " +
            "with the debug key (fine for testing, not for long-term distribution)."
    )
}

// -----------------------------------------------------------------------------
// Android configuration
// -----------------------------------------------------------------------------
android {
    namespace = "dev.zadalruh.zad_alruh"
    compileSdk = flutter.compileSdkVersion.coerceAtLeast(36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (java.time on older Android).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = zadApplicationId
        minSdk = 26
        targetSdk = flutter.targetSdkVersion.coerceAtLeast(36)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260814")
}

flutter {
    source = "../.."
}
