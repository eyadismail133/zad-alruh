import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// -----------------------------------------------------------------------------
// Variant Classification Helpers
// -----------------------------------------------------------------------------
// Coherent variant classification: Release and Profile task contexts take precedence
// over utility words containing "debug" (e.g. stripReleaseDebugSymbols or DebugMetadata).
fun isReleaseVariantTask(name: String): Boolean {
    return name.contains("Release", ignoreCase = true)
}

fun isProfileVariantTask(name: String): Boolean {
    return name.contains("Profile", ignoreCase = true)
}

fun isDebugVariantTask(name: String): Boolean {
    if (isReleaseVariantTask(name) || isProfileVariantTask(name)) {
        return false
    }
    val sanitized = name
        .replace("DebugSymbols", "", ignoreCase = true)
        .replace("DebugMetadata", "", ignoreCase = true)
    return sanitized.contains("Debug", ignoreCase = true)
}

// -----------------------------------------------------------------------------
// Baseline Identity & Task Flags
// -----------------------------------------------------------------------------
val developmentAppId = "dev.zadalruh.zad_alruh"

// Diagnostic unsigned release switch (strictly non-publishable for local diagnosis only)
val allowUnsignedRelease = providers.gradleProperty("allowUnsignedRelease").orNull?.toBoolean()
    ?: (project.findProperty("allowUnsignedRelease")?.toString()?.toBoolean() ?: false)

val hasExplicitDebugRequested = gradle.startParameter.taskNames.any { isDebugVariantTask(it) }
val isExplicitReleaseTaskRequested = gradle.startParameter.taskNames.any { isReleaseVariantTask(it) }

// Guard: Reject combined debug + release tasks at configuration phase to prevent
// defaultConfig.applicationId cross-contamination between variants
if (hasExplicitDebugRequested && isExplicitReleaseTaskRequested) {
    throw GradleException(
        """
        Combined debug and release tasks detected in a single invocation:
        ${gradle.startParameter.taskNames}

        Running debug and release tasks together in the same command is prohibited because
        'defaultConfig.applicationId' cannot simultaneously apply the production Application ID
        to release and the development ID to debug.

        Please execute debug and release builds separately:
          - Debug: './gradlew :app:assembleDebug' or 'flutter build apk --debug'
          - Release: './gradlew :app:assembleRelease', './gradlew :app:bundleRelease', or 'flutter build appbundle'
        """.trimIndent()
    )
}

// -----------------------------------------------------------------------------
// Owner Signing & Release Configuration Loading
// -----------------------------------------------------------------------------
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
val hasKeyProperties = keyPropertiesFile.exists()

if (hasKeyProperties) {
    keyPropertiesFile.inputStream().use { stream ->
        keyProperties.load(stream)
    }
}

// Distinct lexical variables. Preserve raw passwords and keyAlias strings without .trim()
// to prevent mutating legitimate credentials with intentional leading/trailing spaces.
val ownerStoreFilePath: String? = keyProperties.getProperty("storeFile")?.trim()
    ?: keyProperties.getProperty("keystorePath")?.trim()
val ownerStorePassword: String? = keyProperties.getProperty("storePassword")
val ownerKeyAlias: String? = keyProperties.getProperty("keyAlias")
val ownerKeyPassword: String? = keyProperties.getProperty("keyPassword")
val ownerReleaseAppId: String? = keyProperties.getProperty("releaseApplicationId")?.trim()

// Resolve keystore file relative to rootProject (android/) or preserve absolute paths:
val isStoreFileProvided = !ownerStoreFilePath.isNullOrBlank()
val ownerStoreFile: File? = if (isStoreFileProvided) {
    val rawFile = File(ownerStoreFilePath!!)
    if (rawFile.isAbsolute) {
        rawFile
    } else {
        rootProject.file(ownerStoreFilePath)
    }
} else null

// -----------------------------------------------------------------------------
// Validation Logic
// -----------------------------------------------------------------------------
fun ensureOwnerKeyPropertiesPresent(targetTasks: List<String>) {
    if (!hasKeyProperties) {
        throw GradleException(
            """
            Release build failed: Owner signing configuration 'android/key.properties' is missing.
            Target release tasks: $targetTasks

            Release builds require owner upload credentials and an approved releaseApplicationId.
            To fix this:
            1. Copy 'android/key.properties.example' to 'android/key.properties'.
            2. Configure valid storeFile, storePassword, keyAlias, and keyPassword.
            3. Configure an explicit, owner-approved releaseApplicationId (cannot be development ID).

            To produce an unsigned diagnostic release artifact for local testing only:
            Pass '-PallowUnsignedRelease=true' or set 'ORG_GRADLE_PROJECT_allowUnsignedRelease=true'.
            (Diagnostic unsigned artifacts use development ID '$developmentAppId' and are strictly non-publishable).
            """.trimIndent()
        )
    }
}

fun validateReleaseApplicationId(appId: String?) {
    if (appId.isNullOrBlank()) {
        throw GradleException(
            """
            Release build failed: 'releaseApplicationId' is missing or blank in 'android/key.properties'.
            An explicit, owner-approved production Application ID is mandatory for release builds.
            Implicitly publishing under the development ID '$developmentAppId' is strictly forbidden.
            """.trimIndent()
        )
    }
    val trimmed = appId.trim()
    if (trimmed == developmentAppId) {
        throw GradleException(
            """
            Release build failed: 'releaseApplicationId' in 'android/key.properties' is set to development ID '$developmentAppId'.
            Normal release builds require an explicit, approved production Application ID.
            If the development ID is ever chosen by the owner for production, that requires an explicit, accepted review context.
            """.trimIndent()
        )
    }
    val placeholderKeywords = listOf(
        "example", "placeholder", "changeme", "todo", "replace_", "your_application_id", "your.application.id"
    )
    if (placeholderKeywords.any { trimmed.lowercase().contains(it) }) {
        throw GradleException(
            """
            Release build failed: Configured releaseApplicationId '$trimmed' contains placeholder text.
            A valid, owner-approved Android Application ID must be provided.
            """.trimIndent()
        )
    }
    val appIdRegex = Regex("""^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$""")
    if (!appIdRegex.matches(trimmed)) {
        throw GradleException(
            """
            Release build failed: Configured releaseApplicationId '$trimmed' is invalid.
            Android Application IDs must consist of at least two segments separated by dots,
            and each segment must start with a letter and contain only alphanumeric characters or underscores.
            """.trimIndent()
        )
    }
}

// Application ID determination with coherent validation ordering:
// For normal release builds, ensure key.properties is present before validating releaseApplicationId.
val effectiveApplicationId: String = if (isExplicitReleaseTaskRequested && !allowUnsignedRelease) {
    ensureOwnerKeyPropertiesPresent(gradle.startParameter.taskNames)
    validateReleaseApplicationId(ownerReleaseAppId)
    ownerReleaseAppId!!
} else {
    developmentAppId
}

val isStorePasswordProvided = !ownerStorePassword.isNullOrBlank()
val isKeyAliasProvided = !ownerKeyAlias.isNullOrBlank()
val isKeyPasswordProvided = !ownerKeyPassword.isNullOrBlank()

val hasPlaceholderCredentials = (ownerStorePassword?.contains("REPLACE_") == true) ||
    (ownerStorePassword?.contains("YOUR_") == true) ||
    (ownerKeyAlias?.contains("REPLACE_") == true) ||
    (ownerKeyAlias?.contains("YOUR_") == true) ||
    (ownerKeyPassword?.contains("REPLACE_") == true) ||
    (ownerKeyPassword?.contains("YOUR_") == true) ||
    (ownerStoreFilePath?.contains("/path/to/") == true)

val hasAllSigningFields = isStoreFileProvided && isStorePasswordProvided && isKeyAliasProvided && isKeyPasswordProvided
val hasValidStoreFile = ownerStoreFile != null && ownerStoreFile.exists() && ownerStoreFile.isFile && ownerStoreFile.canRead()

// allowUnsignedRelease=true forces signingConfig=null even if valid owner key.properties exists:
val hasValidSigning = !allowUnsignedRelease && hasKeyProperties && hasAllSigningFields && hasValidStoreFile && !hasPlaceholderCredentials

// -----------------------------------------------------------------------------
// Android Configuration
// -----------------------------------------------------------------------------
android {
    namespace = "dev.zadalruh.zad_alruh"
    compileSdk = flutter.compileSdkVersion.coerceAtLeast(36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = effectiveApplicationId
        minSdk = 26
        targetSdk = flutter.targetSdkVersion.coerceAtLeast(36)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasValidSigning) {
            create("release") {
                storeFile = ownerStoreFile
                storePassword = ownerStorePassword
                keyAlias = ownerKeyAlias
                keyPassword = ownerKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasValidSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = null
            }
        }
    }
}

// -----------------------------------------------------------------------------
// Task Graph Guards
// -----------------------------------------------------------------------------
gradle.taskGraph.whenReady {
    val scheduledDebugTasks = allTasks.filter { task -> isDebugVariantTask(task.name) }
    val scheduledReleaseTasks = allTasks.filter { task -> isReleaseVariantTask(task.name) }

    // Guard 1: Reject combined debug + release tasks in the scheduled graph (e.g. via aggregate 'assemble' or 'build')
    if (scheduledDebugTasks.isNotEmpty() && scheduledReleaseTasks.isNotEmpty()) {
        throw GradleException(
            """
            Combined debug and release tasks scheduled in the same task graph:
            Debug tasks: ${scheduledDebugTasks.map { it.name }}
            Release tasks: ${scheduledReleaseTasks.map { it.name }}

            Simultaneous execution of debug and release tasks (e.g. via aggregate tasks like 'assemble' or 'build')
            is prohibited to prevent application ID cross-contamination between debug and release variants.

            Please execute debug and release builds in separate invocations:
              - Debug: './gradlew :app:assembleDebug' or 'flutter build apk --debug'
              - Release: './gradlew :app:assembleRelease', './gradlew :app:bundleRelease', or 'flutter build appbundle'
            """.trimIndent()
        )
    }

    if (scheduledReleaseTasks.isNotEmpty()) {
        // Case A: Diagnostic unsigned release explicitly requested
        if (allowUnsignedRelease) {
            logger.warn("====================================================================")
            logger.warn("WARNING: Diagnostic unsigned release build permitted by flag (-PallowUnsignedRelease=true).")
            logger.warn("Target tasks: ${scheduledReleaseTasks.map { it.name }}")
            logger.warn("Application ID: $developmentAppId")
            logger.warn("Signing Config: null (unsigned artifact; owner keys bypassed if present)")
            logger.warn("This artifact is strictly NON-PUBLISHABLE and for local diagnostics only.")
            logger.warn("====================================================================")
            return@whenReady
        }

        // Case B: Release tasks scheduled via aggregate task without explicit release target
        if (!isExplicitReleaseTaskRequested) {
            throw GradleException(
                """
                Release build aborted: Aggregate task execution detected containing release tasks:
                ${scheduledReleaseTasks.map { it.name }}

                Building normal release artifacts via aggregate tasks without explicit release targets
                is prohibited to ensure coherent variant configuration.
                Normal release artifacts can never be created with the default ID through aggregate aliases.

                Please invoke explicit release tasks directly:
                  - flutter build apk --release
                  - flutter build appbundle
                  - ./gradlew :app:assembleRelease
                  - ./gradlew :app:bundleRelease
                """.trimIndent()
            )
        }

        // Case C: Missing key.properties (validated first before application ID)
        ensureOwnerKeyPropertiesPresent(scheduledReleaseTasks.map { it.name })

        // Case D: Missing or invalid releaseApplicationId
        validateReleaseApplicationId(ownerReleaseAppId)

        // Case E: Incomplete or invalid signing credentials
        if (!hasAllSigningFields || hasPlaceholderCredentials || !hasValidStoreFile) {
            val missingOrInvalid = mutableListOf<String>()
            if (!isStoreFileProvided) missingOrInvalid.add("storeFile is missing or empty")
            if (!isStorePasswordProvided) missingOrInvalid.add("storePassword is missing or empty")
            if (!isKeyAliasProvided) missingOrInvalid.add("keyAlias is missing or empty")
            if (!isKeyPasswordProvided) missingOrInvalid.add("keyPassword is missing or empty")
            if (hasPlaceholderCredentials) missingOrInvalid.add("Placeholder template values detected; real owner credentials required")
            if (ownerStoreFile != null && !ownerStoreFile.exists()) {
                missingOrInvalid.add("Keystore file not found at: ${ownerStoreFile.path}")
            } else if (ownerStoreFile != null && ownerStoreFile.isDirectory) {
                missingOrInvalid.add("Keystore path points to a directory, not a file: ${ownerStoreFile.path}")
            } else if (ownerStoreFile != null && !ownerStoreFile.canRead()) {
                missingOrInvalid.add("Keystore file is not readable: ${ownerStoreFile.path}")
            }

            throw GradleException(
                """
                Release build failed: Incomplete or invalid owner signing configuration in 'android/key.properties'.
                Target release tasks: ${scheduledReleaseTasks.map { it.name }}
                Details:
                ${missingOrInvalid.joinToString("\n") { " - $it" }}

                Silent fallback to debug keys or invalid owner configurations is strictly prohibited.
                """.trimIndent()
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260814")
}

flutter {
    source = "../.."
}
