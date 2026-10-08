# Zad Al-Ruh (زادُ الروح) - Android Native Release & Build Configuration Guide

> **STATUS:** Config Implemented — Fresh Verification Gates Pending Codex Execution.<br>
> *This document describes the native Android build configuration established in the repository. It is a configuration implementation and does not make claims of external developer account readiness, human store review approval, or final Play Store publication readiness.*

---

## 1. Scope & System Environment

### 1.1 Scope Boundaries (7 Files Only)
1. `android/app/build.gradle.kts`
2. `android/app/src/main/AndroidManifest.xml`
3. `android/app/src/main/res/xml/backup_rules.xml`
4. `android/app/src/main/res/xml/data_extraction_rules.xml`
5. `android/.gitignore`
6. `android/key.properties.example`
7. `docs/ANDROID-RELEASE-CONFIG.md`

*No Dart source code, pubspec dependencies, app icons, iOS configurations, or existing audio assets (including raw WAV files) were modified.*

### 1.2 Toolchain Baseline & Environment Note
- **Workspace Junction:** `D:\tools\zad-alruh-workspace`
- **Flutter SDK:** 3.47.5
- **Android SDK:** `D:\tools\android-sdk`
- **Android Gradle Plugin (AGP):** 9.1.0
- **Kotlin Gradle Plugin:** 2.4.0
- **Java Toolchain:** Java 17 (`JVM_17` target)

> **Environment Platform Note:**<br>
> During environment dry-runs, `:app:assembleDebug` indicated that the third-party dependency `audio_session` requires installed SDK platform `android-35`. Installation of `android-35` in the local build environment is handled separately and does not alter this task's native baseline (`minSdk = 26`, `compileSdk` & `targetSdk >= 36`).

---

## 2. Configuration & Identity Architecture

### 2.1 SDK Levels & Localization
- **`minSdk`:** Explicitly pinned to `26` (Android 8.0 Oreo product support baseline).
- **`compileSdk` & `targetSdk`:** Bound via `.coerceAtLeast(36)` to ensure compatibility with Android 16 / SDK 36 APIs.
- **Application Label:** `android:label="زادُ الروح"`.
- **RTL Support:** `android:supportsRtl="true"` explicitly declared for native Arabic layout direction.
- **Activity Class Name:** Declared with fully-qualified class `android:name="dev.zadalruh.zad_alruh.MainActivity"` to avoid runtime `ClassNotFoundException` under custom release application IDs.

### 2.2 Application ID Rules & Coherent Validation Ordering
- **Development / Debug / Diagnostic Unsigned ID:** Strictly preserved as `dev.zadalruh.zad_alruh`. Local developer phone updates, local databases, and diagnostic artifacts remain completely intact.
- **Owner Normal Release ID:** **Mandatory in `android/key.properties`** (`releaseApplicationId=...`).
  - Validation order is strictly coherent: the existence of `android/key.properties` is validated and reported **first** before evaluating `releaseApplicationId`.
  - Cannot be omitted or blank.
  - Cannot use the development ID `dev.zadalruh.zad_alruh` (preventing accidental publication under development namespace; any future use of development ID in production requires explicit owner acceptance).
  - Cannot use placeholder strings (`example`, `placeholder`, `changeme`, `todo`, `replace_`).
  - Must conform to standard Android package syntax (`^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$`).

---

## 3. Combined & Aggregate Task Guarding

In Android Gradle projects without flavors, `defaultConfig.applicationId` is a single property evaluated during the Gradle configuration phase. If debug and release tasks run within the same command, applying the production ID to release would silently apply it to debug as well, causing cross-contamination.

To prevent this:
1. **Coherent Variant Classification:** The guard uses strict variant classification helpers (`isReleaseVariantTask`, `isProfileVariantTask`, `isDebugVariantTask`). Release and Profile variant contexts take precedence over utility words containing "debug" (such as `stripReleaseDebugSymbols` or `DebugMetadata`), ensuring legitimate AGP release tasks are never misclassified as debug variant tasks.
2. **Configuration-Phase Guard:** Detects if both actual debug and release tasks are passed in `gradle.startParameter.taskNames` (e.g. `./gradlew assembleDebug assembleRelease`) and halts immediately with an actionable error.
3. **Graph-Phase Guard:** Detects if both actual debug and release tasks are scheduled in the actual execution graph (e.g. via aggregate tasks like `./gradlew assemble` or `./gradlew build`) and halts execution before any compilation starts.
4. **Requirement:** Debug and release tasks must be run in **separate invocations**:
   - Debug: `flutter build apk --debug` or `./gradlew :app:assembleDebug`
   - Release: `flutter build apk --release`, `flutter build appbundle`, `./gradlew :app:assembleRelease`, or `./gradlew :app:bundleRelease`

---

## 4. Device-Only Privacy & Auto Backup Architecture

### 4.1 Nine Supported Storage Domains
Per official Android Data Backup documentation ([Android Auto Backup](https://developer.android.com/identity/data/autobackup)), the Android system supports 9 standard and device-protected storage domains for backup and extraction exclusion:
1. `root`
2. `file`
3. `database`
4. `sharedpref`
5. `external`
6. `device_root`
7. `device_file`
8. `device_database`
9. `device_sharedpref`

*(Note: Cache and no-backup directories are automatically excluded by the Android OS; no synthetic cache XML tags are required).*

### 4.2 Dual XML Exclusion Rules
`android:allowBackup="false"` alone disables Google Drive cloud backup, but on Android 12+ (API 31+), OEM device-to-device migration (e.g. cable transfer during setup) operates under data extraction rules.

1. **`android:allowBackup="false"`** on `<application>`.
2. **`android:fullBackupContent="@xml/backup_rules"`** for legacy Android (API 26–30):
   Excludes all 9 storage domains with `path="."`.
3. **`android:dataExtractionRules="@xml/data_extraction_rules"`** for modern Android 12+ (API 31+):
   Excludes all 9 storage domains with `path="."` for both `<cloud-backup>` and `<device-transfer>`.

> **Privacy Scope Clarification:**<br>
> These XML exclusion rules instruct the standard Android OS backup and transfer frameworks to exclude local application databases, Quran reading progress bookmarks, and prayer settings. They do not constitute an absolute cryptographic guarantee against modified OEM ROMs, rooted device file extraction, or physical ADB debugging exports.

---

## 5. Network & Permissions Architecture

- **`android.permission.INTERNET`:** Declared on `<manifest>` in preparation for approved upcoming manual Quran audio streaming over HTTPS.
- **`android:usesCleartextTraffic="false"`:** Declared on `<application>` to strictly prohibit unencrypted HTTP cleartext traffic.
- **Permissions Audit:** Zero runtime or dangerous permissions added (no microphone, no location, no foreground service, no exact alarms, no analytics).
- **Status:** Network-dependent streaming features remain pending implementation in Dart application code.

---

## 6. Owner Signing & Release Gating

### 6.1 Raw Credential Handling
- `storePassword`, `keyAlias`, and `keyPassword` are preserved as exact raw strings **without `.trim()`** to prevent mutating legitimate credentials that deliberately contain leading or trailing whitespace.
- File path (`storeFile`) and `releaseApplicationId` are trimmed appropriately.

### 6.2 Diagnostic Unsigned Release Switch (`allowUnsignedRelease`)
- Enabled via project property `-PallowUnsignedRelease=true` or environment variable `ORG_GRADLE_PROJECT_allowUnsignedRelease=true`.
- **Behavior:** Reads `key.properties` if present, but **strictly bypasses owner credentials and forces `signingConfig = null` (unsigned artifact)**.
- Application ID is locked to `dev.zadalruh.zad_alruh`.
- Emits prominent console warnings: `This artifact is strictly NON-PUBLISHABLE and for local diagnostics only.`

### 6.3 Normal Release Build Guarding
Release tasks are inspected in `gradle.taskGraph.whenReady`:
1. **Missing `key.properties`:** Validated and reported **first** with actionable guidance.
2. **Missing / Invalid `releaseApplicationId`:** Validated next; rejects default development ID or placeholders.
3. **Keystore File Verification:** Verified relative to `rootProject` (`android/upload-keystore.jks`) or absolute path; verifies that file exists, is a regular file (not directory), and is readable.
4. **No Secret Leaks:** Passwords and keys are never printed in logs or exceptions.

---

## 7. Owner Setup Instructions

The repository contains no signing credentials. The project owner must perform this setup:

### Step 1: Generate Upload Keystore
From terminal using JDK 17 `keytool`:
```powershell
keytool -genkey -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### Step 2: Create `android/key.properties`
```powershell
Copy-Item android/key.properties.example android/key.properties
```

### Step 3: Populate Credentials
Edit `android/key.properties`:
```properties
storeFile=upload-keystore.jks
storePassword=REPLACE_WITH_OWNER_KEYSTORE_PASSWORD
keyAlias=REPLACE_WITH_OWNER_KEY_ALIAS
keyPassword=REPLACE_WITH_OWNER_KEY_PASSWORD
releaseApplicationId=com.zad.alruh
```

### Step 4: Verify Git Ignore Status
```powershell
git status --ignored
```
*(Confirm `key.properties` and keystores appear under ignored files).*

---

## 8. Verification Gates (To Be Executed by Codex)

> **Execution Notice:**<br>
> In accordance with strict instructions, verification commands were **NOT RUN** during this implementation lane. All gates are defined below for Codex execution from `D:\tools\zad-alruh-workspace`.

### Gate 1: Gradle Configuration & Debug Build (Without Owner Key)
```powershell
flutter build apk --debug
```
*Expected Result:* Clean build, outputting debug APK with ID `dev.zadalruh.zad_alruh`. IDE sync and `./gradlew app:tasks --all` run unaffected.

### Gate 2: Release Failure Verification (Without Key / ID)
```powershell
flutter build appbundle
```
*Expected Result:* Build aborted with actionable exception:
```
Release build failed: Owner signing configuration 'android/key.properties' is missing.
Target release tasks: [:app:bundleRelease]
```

### Gate 3: Combined / Aggregate Task Trap Verification
```powershell
./gradlew assemble
# or
./gradlew assembleDebug assembleRelease
```
*Expected Result:* Aborts immediately:
```
Combined debug and release tasks scheduled in the same task graph...
Simultaneous execution of debug and release tasks (e.g. via aggregate tasks like 'assemble' or 'build') is prohibited...
```

### Gate 4: Diagnostic Unsigned Release (With and Without Key)
```powershell
$env:ORG_GRADLE_PROJECT_allowUnsignedRelease="true"
flutter build apk --release
```
*Expected Result:* Emits warning, forces `signingConfig = null`, uses `dev.zadalruh.zad_alruh`, and outputs unsigned diagnostic artifact.

### Gate 5: Manifest & AAPT Verification
```powershell
& "D:\tools\android-sdk\build-tools\36.0.0\aapt.exe" dump badging build\app\outputs\flutter-apk\app-debug.apk
```
*Verify:*
- `sdkVersion:'26'`
- `targetSdkVersion:'36'`
- `application-label:'زادُ الروح'`
- RTL enabled
- `android.permission.INTERNET` declared
- `usesCleartextTraffic='false'`

### Gate 6: Git Diff Verification
```powershell
git diff
```
*Verify:* Only the 7 scoped files are modified.

---

## 9. Remaining External Requirements & Limitations

1. **Config Implementation Only:** Prepares repository native Android files; does not represent full Google Play Store release readiness.
2. **External Owner Prerequisites:** Google Play Console developer account registration, actual owner key generation, privacy policy document publication, and human review gates remain pending.
3. **Audio & Quran Runtime:** HTTPS audio streaming and Quran page display are decoupled tasks in separate lanes.
4. **iOS Platform:** iOS toolchain, Info.plist declarations, and Apple developer certificates remain pending for macOS-based phases.
