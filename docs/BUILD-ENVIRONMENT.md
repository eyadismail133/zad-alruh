# Build environment and validation

## Pinned development tools

- Flutter 3.47.5, Dart 3.13.4: `D:\tools\flutter\bin` (official Flutter tag, commit 6a19cca56475dbfba1478ee68d7bd0c2ef891da1).
- Android SDK: `D:\tools\android-sdk`; API 36, build tools 36.0.0, NDK 28.2.13676358.
- Java: installed Eclipse Adoptium JDK 21. Flutter-generated Android source currently targets Java 17.
- These paths are machine-local tooling, not bundled application assets.

## Windows build workaround

The installed Java runtime fails to load Gradle's wrapper through an absolute classpath containing this project's Arabic directory name. Loading the same wrapper through a relative path or an ASCII path works. `D:\tools\zad-alruh-workspace` is a verified directory junction pointing to `D:\projects\زادُ الروح`; it exposes the same checkout and does not duplicate or move project files. Run Android builds from that alias. Never recursively delete the junction as cleanup.

Java's initial Gradle downloads also stalled on the default network stack. A child-process-only `JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true` allowed the download to progress. No TLS checks were disabled and no global network permissions changed.

Example PowerShell environment for Android validation:

```powershell
$env:PATH = 'D:\tools\flutter\bin;' + $env:PATH
$env:ANDROID_HOME = 'D:\tools\android-sdk'
$env:ANDROID_SDK_ROOT = 'D:\tools\android-sdk'
$env:GRADLE_USER_HOME = 'D:\tools\gradle-ipv4-test'
$env:JAVA_TOOL_OPTIONS = '-Djava.net.preferIPv4Stack=true'
Set-Location -LiteralPath 'D:\tools\zad-alruh-workspace'
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

These are commands to run, not claims that the gates have passed. Actual results belong in the milestone review records.

## Release prerequisites

The generated application identifier is a development placeholder. The owner-controlled identifier and signing configuration must be supplied before upload. A debug-signed release artifact is not suitable for delivery. Release checks must reject missing content/rights/religious review and incomplete owner configuration.

iOS source can be prepared on Windows, but iOS compilation, signing and real-device verification require macOS/Xcode and an iPhone. Neither is available in this environment. Android hardware is not currently attached. Unit/widget tests do not establish background audio, OS permission, battery restriction or screen-reader acceptance on physical devices.

Gradle9.3.1 archive download was recovered through standard ranged requests after transport interruptions. Its assembled SHA256 matched the official published checksum17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43. The verified archive was placed into the local wrapper cache; gradlew --version succeeded. A running Android build remains a separate gate. This tooling recovery changes no global security policy.

## 16 KB runtime test attempt

Android Emulator 37.1.11 and official `system-images;android-36;google_apis_ps16k;x86_64` revision7 are installed. AVD `zad_api36_16k` was created. `emulator -accel-check` reports code6: the Android Emulator hypervisor driver is unavailable; Windows reports HypervisorPresent=false. A headless `-accel off -gpu swiftshader` attempt exited before an adb device became available. No driver, Windows feature or firmware setting was changed. Installation does not satisfy runtime acceptance: actual `getconf PAGESIZE`=16384 and application tests on a running supported environment remain pending. Static ELF/ZIP alignment checks should run once an APK is built, and physical-device audio/permission tests remain separate.

## Initial APK static alignment evidence

The debug APK at the delta06 snapshot built successfully both in the cold build and a fresh incremental run (44.6s). SHA256: 246671F3F9CF7E32E7A24715BD2A037ECF00B2F3ABE035AEFABC5E794193C64E. This is a development APK, not a distributable store release.

All seven packaged native libraries passed LOAD alignment >=16384 and APK zipalign -c -P16 4 exited0. A stricter GNU_RELRO check found non-aligned ends in libflutter.so and libsqlite3.so for arm64-v8a/x86_64; armeabi-v7a and arm64 Vulkan validation library passed. For example Flutter arm64 VirtAddr0x2483330+MemSize0x091cd0=0x2515000 (remainder0x1000), SQLite arm64 0x1a4630+0x29d0=0x1a7000 (remainder0x3000). Current official guidance requires aligned RELRO ends: https://developer.android.com/guide/practices/page-sizes#relro . These prebuilt dependency findings must be investigated on profile/release artifacts and resolved before 16KB release acceptance; LOAD/ZIP success alone is insufficient. No binary patch or security-flag removal was applied. Detailed local results: .local/android-native-alignment-results.json. Runtime verification remains pending a running supported device/environment.

Profile APK verification: build passed94.8s,75.6MB, SHA256 BC8722EE68872A00890186C48E6A20C33AEEFE9466C625D6FA14152527C6450A. All12nativeLOAD checks and APKzipalign passed, but GNU_RELRO end checks failed libflutter.so on all3ABIs and libsqlite3.so onarm64/x64. AppAOT and vmservice libraries passed. Local evidence .local/native-profile-alignment-results.json/.log. This shows the static finding is not limited to debug artifacts; it does not establish a runtime crash. Investigate prebuilt engine/SQLite compatibility and production packaging before release qualification; do not remove RELRO or patch binary headers to mask it. No store release built or signed.

Additional profile layout investigation on2026-09-27: in all six RELRO-bearing libraries, the next independent writable LOAD begins after the RELRO end rounded up to16KB. Thus the documented crash mechanism (rounded RELRO overlaps subsequently writable data) has not been established for these artifacts. This is an inference from actual ELF headers and current Bionic linker source https://android.googlesource.com/platform/bionic/+/refs/heads/main/linker/linker_phdr.cpp , not runtime proof. The stricter official end-alignment finding remains; no known crash or completed16KB compatibility is claimed. Local layouts:.local/native-relro-layout-investigation.json. Actual release artifact and16KB runtime tests remain required before release acceptance.
