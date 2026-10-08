# Technical Platform Branding & Asset Specifications

## 1. Overview & Source Asset Integrity
Platform branding for **زاد الروح** is derived deterministically from the supplied master asset:
- **Source Path**: `assets/branding/logo.png`
- **Format**: RGBA PNG (1280×1280)
- **Palette**: Forest green `#15543F` and gold `#D5B469` / `#D2AE55` arch with Quran on a wooden stand (rehal), illuminated by crescent moon and celestial rays.
- **Integrity**: Source file SHA bytes are strictly preserved and immutable. No brand redesign, typography alterations, or synthetic imagery are introduced. The master logo is strictly read-only and never overwritten.

---

## 2. Security & Containment Architecture (`tool/export_branding.py`)

### 2.1 Canonical Root Resolution & Exact Lexical Paths
- **Single Canonical Root**: Resolved exactly once at startup:
  `anchor_root = script_path.parent.parent.resolve()`
  (where `script_path = Path(__file__).resolve()`).
  Arbitrary `--root` CLI arguments are eliminated to prevent arbitrary redirection.
- **Exact Lexical Paths Retained**: All key resource paths retain their exact lexical forms under `anchor_root`:
  * Master Logo: `anchor_root / "assets" / "branding" / "logo.png"`
  * Android Res: `anchor_root / "android" / "app" / "src" / "main" / "res"`
  * iOS Asset Catalog: `anchor_root / "ios" / "Runner" / "Assets.xcassets"`
  * iOS AppIcon Set: `anchor_root / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"`
  * iOS LaunchImage Set: `anchor_root / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"`

### 2.2 Lexical-Before-Canonical Reparse & Junction Defense
1. **Lstat Inspection Before Any Resolve**:
   - `validate_no_reparse_below_anchor(path, anchor_root)` inspects every path component strictly **below** `anchor_root` using `is_reparse_or_link()` (`os.lstat()` checking `FILE_ATTRIBUTE_REPARSE_POINT` `0x400` and `path.is_symlink()`).
   - **Direct Check Without `exists()`**: `is_reparse_or_link` is called directly on each lexical component rather than checking `curr.exists()`. Because `Path.exists()` follows links and evaluates to `False` for dangling symlinks or reparse points pointing to nonexistent targets, evaluating `is_reparse_or_link` directly prevents dangling links to nonexistent files/siblings from bypassing preflight.
   - **Crucial Order**: This check runs **before** calling `.resolve()` on any directory, master logo, or target path. Calling `.resolve()` prematurely would follow a directory junction to its target, hiding the junction and allowing writes to an unapproved destination inside the root.
   - Any reparse point, junction, or symlink below `anchor_root` triggers an immediate `PreflightSecurityError`.
2. **Canonical Containment Proof**:
   - Only **after** lexical reparse validation passes are `.resolve()` calls permitted.
   - Enforces that `resolved_target.relative_to(resolved_anchor)` and `resolved_expected.relative_to(resolved_anchor)` both succeed, and `resolved_target.relative_to(resolved_expected)` succeeds.
   - Master logo collision check: `resolved_target != resolved_logo`.

### 2.3 Manifest & Exact Tuple Set Validation
1. **iOS AppIcon (`AppIcon.appiconset/Contents.json`)**:
   - Enforces the **EXACT approved 19-tuple set** of `(filename, size, scale, idiom)` entries.
   - Rejects duplicate tuples, unsupported idioms (e.g. watch/carplay), mismatched dimensions, or arbitrary extra entries.
   - Correctly permits legitimate shared filenames between iPhone and iPad entries (e.g. `Icon-App-20x20@2x.png` shared between `("20x20", "2x", "iphone")` and `("20x20", "2x", "ipad")`).
   - Maps to exactly 15 unique approved image targets with exact pixel dimensions.
2. **iOS LaunchImage (`LaunchImage.imageset/Contents.json`)**:
   - Enforces the **EXACT approved 3-tuple set** of `(filename, scale, idiom)` entries (`1x`, `2x`, `3x` universal).
   - Rejects arbitrary extras, invalid scales, or non-universal idioms.
3. **Android Assets**:
   - Fixed approved densities for legacy icons (48, 72, 96, 144, 192px), adaptive foregrounds (108, 162, 216, 324, 432px), monochrome silhouettes, and launch images.

### 2.4 Strict XML Verification & Atomic Exit
- All 13 Android XML and iOS Storyboard configuration files are checked for lexical reparse safety, existence, and well-formed XML syntax.
- Any missing or malformed XML configuration file immediately fails preflight or sets `--verify` mode to failed, guaranteeing a **nonzero exit code** (`sys.exit(1)` or `sys.exit(3)`).
- Zero directories created (`mkdir`) and zero files written if preflight fails.

---

## 3. Technical Asset Geometry & Platform Configurations

### 3.1 Android Adaptive & Legacy Icons
1. **Adaptive Icon Geometry (API 26+)**:
   - Standard 108dp base canvas (`108×108` mdpi up to `432×432` xxxhdpi).
   - The logo artwork bounding box is strictly scaled to fit within the **central 66dp safe zone** (`66px` at mdpi up to `264px` at xxxhdpi). Masks (circle, rounded rect, squircle) will never clip the arch or bookstand.
   - Background: XML color drawable `@drawable/ic_launcher_background` (`#15543F`).
   - Foreground: Transparent RGBA PNGs placed in density folders (`drawable-mdpi`, `drawable-hdpi`, `drawable-xhdpi`, `drawable-xxhdpi`, `drawable-xxxhdpi`).
   - Defined in: `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`.

2. **Themed Icons Monochrome Layer (API 33+)**:
   - Layer: `@drawable/ic_launcher_monochrome`.
   - Generated directly from the logo's existing alpha channel into a flat white silhouette layer, preserving source alpha anti-aliasing without colored raster conversion.
   - Defined in: `android/app/src/main/res/mipmap-anydpi-v33/ic_launcher.xml`.

3. **Legacy Square Icons (< API 26)**:
   - Densities: mdpi (48×48), hdpi (72×72), xhdpi (96×96), xxhdpi (144×144), xxxhdpi (192×192).
   - Format: Opaque RGB PNGs with solid brand forest green (`#15543F`) background and safely inset logo.

### 3.2 Android Splash Screens
1. **Pre-API 31 (Android 11 and lower)**:
   - Configured in `android/app/src/main/res/drawable/launch_background.xml` and `drawable-v21/launch_background.xml`.
   - Uses `layer-list` with `@color/launch_background_color` (cream light `#FBF8F0` in `values/colors.xml`, forest green `#15543F` in `values-night/colors.xml`).
   - Centered logo: `<bitmap android:gravity="center" android:src="@drawable/launch_image" />`.

2. **Android 12+ (API 31+) Splash System**:
   - Configured in `values-v31/styles.xml` and `values-night-v31/styles.xml`.
   - Attributes:
     - `android:windowSplashScreenBackground`: `@color/launch_background_color` (cream `#FBF8F0` / dark `#15543F`).
     - `android:windowSplashScreenAnimatedIcon`: `@drawable/ic_splash_icon` referencing `@drawable/launch_image` centered within safe 160dp window.
     - No spinning animations or artificial time delays.
   - Preserves Flutter embedding `NormalTheme` (`?android:colorBackground`) semantics across all versions.

### 3.3 iOS AppIcon & LaunchScreen
1. **AppIcon Set (`ios/Runner/Assets.xcassets/AppIcon.appiconset`)**:
   - 15 static approved unique filenames matching the 19 valid `Contents.json` tuples:
     - 20×20 @1x, @2x, @3x (20px, 40px, 60px)
     - 29×29 @1x, @2x, @3x (29px, 58px, 87px)
     - 40×40 @1x, @2x, @3x (40px, 80px, 120px)
     - 60×60 @2x, @3x (120px, 180px)
     - 76×76 @1x, @2x (76px, 152px)
     - 83.5×83.5 @2x (167px)
     - 1024×1024 @1x (1024px)
   - Color Mode: Strictly opaque RGB (0 alpha channel) with `#15543F` forest green background.
   - App Store 1024×1024 marketing icon: strictly opaque RGB, no alpha, no rounded corners baked in.

2. **LaunchScreen Storyboard & LaunchImage**:
   - `ios/Runner/Base.lproj/LaunchScreen.storyboard`:
     - Centered `UIImageView` with `contentMode="scaleAspectFit"`.
     - Explicit width `160` and height `160` Auto Layout constraints.
     - Background color: cream `#FBF8F0` (`r=0.984, g=0.973, b=0.941`).
   - `LaunchImage.imageset`:
     - 1x: 160×160 px
     - 2x: 320×320 px
     - 3x: 480×480 px

3. **iOS Platform Identity**:
   - `ios/Runner/Info.plist`:
     - `CFBundleDisplayName`: `زاد الروح`
     - `CFBundleName`: `زاد الروح`
   - Zero unnecessary permissions or ATS exceptions added.

---

## 4. Execution & Verification Instructions

The generator script is self-contained in `tool/export_branding.py` and uses Pillow.

> **Execution Command for Root / Operator (DO NOT EXECUTE DURING READ-ONLY PHASES)**:
```powershell
C:\Users\dell\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe tool/export_branding.py
```

### 4.1 Verification & Safe Execution Modes
1. **Internal Invariant Self-Check (In-memory verification of validation rules, tuple sets, simulated junction defense, dangling symlink detection, and XML configs)**:
```powershell
C:\Users\dell\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe tool/export_branding.py --selfcheck
```

2. **True Zero-Write Dry-Run (Runs strict preflight without writing any files or creating directories)**:
```powershell
C:\Users\dell\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe tool/export_branding.py --dry-run
```

3. **Read-Only Verification (Validates master logo, XML configurations, and on-disk files without modifications)**:
```powershell
C:\Users\dell\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe tool/export_branding.py --verify
```

4. **JSON Diagnostic Output**:
```powershell
C:\Users\dell\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe tool/export_branding.py --verify --json
```

---

## 5. Parent Contained Disposable Windows Fixture Reproduction Guidance

To test the Windows junction and dangling symlink preflight rejection in a clean disposable environment without modifying the repository:

### Test Case A: Internal `AppIcon.appiconset` Directory Junction
1. Copy the project into a temporary fixture folder: `C:\temp\fixture_branding`.
2. Create an alternate directory within the fixture root:
   ```cmd
   mkdir C:\temp\fixture_branding\ios\Runner\alternate_icons
   copy C:\temp\fixture_branding\ios\Runner\Assets.xcassets\AppIcon.appiconset\Contents.json C:\temp\fixture_branding\ios\Runner\alternate_icons\Contents.json
   ```
3. Remove the original folder and replace it with a directory junction pointing to `alternate_icons`:
   ```cmd
   rmdir /s /q C:\temp\fixture_branding\ios\Runner\Assets.xcassets\AppIcon.appiconset
   mklink /J C:\temp\fixture_branding\ios\Runner\Assets.xcassets\AppIcon.appiconset C:\temp\fixture_branding\ios\Runner\alternate_icons
   ```
4. Execute dry-run:
   ```powershell
   python C:\temp\fixture_branding\tool\export_branding.py --dry-run
   ```
5. **Expected Result**: Exits with code `3` (`PREFLIGHT FAILED: Reparse point / junction / symlink detected below workspace root: ...\AppIcon.appiconset`), zero directories created, zero files written.

### Test Case B: Master Logo Ancestor Junction
1. In a similar fixture, replace `fixture_branding\assets\branding` with a directory junction pointing to `alternate_branding`:
   ```cmd
   mklink /J C:\temp\fixture_branding\assets\branding C:\temp\fixture_branding\alternate_branding
   ```
2. Execute dry-run:
   ```powershell
   python C:\temp\fixture_branding\tool\export_branding.py --dry-run
   ```
3. **Expected Result**: Exits with code `3` (`PREFLIGHT FAILED: Reparse point / junction / symlink detected below workspace root: ...\branding`), zero modifications made.

### Test Case C: Dangling Symlink / Reparse Point below Root
1. In a similar disposable fixture, create a symlink for an approved icon filename pointing to a nonexistent sibling:
   ```cmd
   mklink C:\temp\fixture_branding\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@1x.png C:\temp\fixture_branding\ios\Runner\Assets.xcassets\AppIcon.appiconset\nonexistent_sibling.png
   ```
2. Execute dry-run:
   ```powershell
   python C:\temp\fixture_branding\tool\export_branding.py --dry-run
   ```
3. **Expected Result**: Exits with code `3` (`PREFLIGHT FAILED: Reparse point / junction / symlink detected below workspace root: ...\Icon-App-20x20@1x.png`), zero directories created, zero files written.

---

## 6. Current Status & Pending Deliverables
- [x] Generator script secured with strict lexical-before-canonical preflight & exact tuple validators (`tool/export_branding.py`).
- [x] Android XML resources configured (colors, adaptive icons, API 31+ styles, API 33 monochrome).
- [x] iOS LaunchScreen storyboard & Info.plist configured with Arabic display name.
- [ ] Binary raster export execution (**NOT RUN - Pending root execution after Sol approval**).
- [ ] Physical Android device mask verification (**NOT RUN - Pending root/QA**).
- [ ] macOS Xcode build & archive verification (**NOT RUN - Pending root/QA**).
- [ ] Sequential release gates (**NOT RUN - Owned exclusively by Codex**).
