#!/usr/bin/env python3
"""
Zad Alruh Platform Branding Export Generator.

Deterministic rasterization and recomposition of platform brand assets from
assets/branding/logo.png for Android and iOS platforms.

Security & Containment Architecture:
- Root is strictly anchored to script.parent.parent.resolve() (no arbitrary root CLI argument).
- Master logo is strictly read-only and immutable; writes targeting it are rejected.
- All-or-nothing preflight: EVERY output path, parent directory, XML configuration, and
  manifest entry is validated BEFORE any file writing or directory creation (mkdir) occurs.
- Lexical-before-canonical validation:
  * Key paths (assets/branding/logo.png, ios/Runner/Assets.xcassets/AppIcon.appiconset, etc.)
    retain exact lexical paths under canonical root.
  * Every existing ancestor component strictly below canonical root is inspected with
    os.lstat() (checking FILE_ATTRIBUTE_REPARSE_POINT 0x400 and os.readlink) BEFORE calling
    .resolve() on any directory or target. This prevents internal junctions from hiding behind
    early resolution.
  * Canonical resolved target containment in both designated asset directory and anchor root.
- Exact tuple validators:
  * iOS AppIcon: Requires EXACT approved (filename, size, scale, idiom) 19-tuple set. Rejects
    duplicate tuples, unsupported idioms/scales/sizes, and arbitrary extras while correctly
    permitting legitimate shared filenames between iPhone and iPad entries.
  * iOS LaunchImage: Requires EXACT approved (filename, scale, idiom) 3-tuple set. Rejects
    arbitrary extras or mismatched scales/idioms.
- XML verification: Missing or malformed XML configurations cause overall failure and nonzero exit.
- True zero-write --dry-run mode, read-only --verify mode, and in-memory --selfcheck mode.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import xml.etree.ElementTree as ET

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow is required. Install via pip install Pillow", file=sys.stderr)
    sys.exit(1)

# Pillow resampling filter compatibility
RESAMPLE_FILTER = getattr(Image, "Resampling", Image).LANCZOS

# Brand Palette Constants
COLOR_FOREST_GREEN = (21, 84, 63)     # #15543F - Brand primary & icon background
COLOR_CREAM_LIGHT = (251, 248, 240)   # #FBF8F0 - Splash light background
COLOR_DARK_BG = (18, 26, 22)          # #121A16 - Dark theme background

# Exact approved 19-tuple set for iOS AppIcon Contents.json: (filename, size, scale, idiom)
APPROVED_IOS_APP_ICON_ENTRIES: set[tuple[str, str, str, str]] = {
    ("Icon-App-20x20@2x.png", "20x20", "2x", "iphone"),
    ("Icon-App-20x20@3x.png", "20x20", "3x", "iphone"),
    ("Icon-App-29x29@1x.png", "29x29", "1x", "iphone"),
    ("Icon-App-29x29@2x.png", "29x29", "2x", "iphone"),
    ("Icon-App-29x29@3x.png", "29x29", "3x", "iphone"),
    ("Icon-App-40x40@2x.png", "40x40", "2x", "iphone"),
    ("Icon-App-40x40@3x.png", "40x40", "3x", "iphone"),
    ("Icon-App-60x60@2x.png", "60x60", "2x", "iphone"),
    ("Icon-App-60x60@3x.png", "60x60", "3x", "iphone"),
    ("Icon-App-20x20@1x.png", "20x20", "1x", "ipad"),
    ("Icon-App-20x20@2x.png", "20x20", "2x", "ipad"),
    ("Icon-App-29x29@1x.png", "29x29", "1x", "ipad"),
    ("Icon-App-29x29@2x.png", "29x29", "2x", "ipad"),
    ("Icon-App-40x40@1x.png", "40x40", "1x", "ipad"),
    ("Icon-App-40x40@2x.png", "40x40", "2x", "ipad"),
    ("Icon-App-76x76@1x.png", "76x76", "1x", "ipad"),
    ("Icon-App-76x76@2x.png", "76x76", "2x", "ipad"),
    ("Icon-App-83.5x83.5@2x.png", "83.5x83.5", "2x", "ipad"),
    ("Icon-App-1024x1024@1x.png", "1024x1024", "1x", "ios-marketing"),
}

# Mapping of the 15 unique plain filenames to pixel dimension (W, H)
APPROVED_IOS_APP_ICON_FILES: dict[str, tuple[int, int]] = {
    "Icon-App-20x20@1x.png": (20, 20),
    "Icon-App-20x20@2x.png": (40, 40),
    "Icon-App-20x20@3x.png": (60, 60),
    "Icon-App-29x29@1x.png": (29, 29),
    "Icon-App-29x29@2x.png": (58, 58),
    "Icon-App-29x29@3x.png": (87, 87),
    "Icon-App-40x40@1x.png": (40, 40),
    "Icon-App-40x40@2x.png": (80, 80),
    "Icon-App-40x40@3x.png": (120, 120),
    "Icon-App-60x60@2x.png": (120, 120),
    "Icon-App-60x60@3x.png": (180, 180),
    "Icon-App-76x76@1x.png": (76, 76),
    "Icon-App-76x76@2x.png": (152, 152),
    "Icon-App-83.5x83.5@2x.png": (167, 167),
    "Icon-App-1024x1024@1x.png": (1024, 1024),
}

# Exact approved 3-tuple set for iOS LaunchImage Contents.json: (filename, scale, idiom)
APPROVED_IOS_LAUNCH_IMAGE_ENTRIES: set[tuple[str, str, str]] = {
    ("LaunchImage.png", "1x", "universal"),
    ("LaunchImage@2x.png", "2x", "universal"),
    ("LaunchImage@3x.png", "3x", "universal"),
}

# Mapping of the 3 unique plain filenames to pixel dimension (W, H)
APPROVED_IOS_LAUNCH_IMAGE_FILES: dict[str, tuple[int, int]] = {
    "LaunchImage.png": (160, 160),
    "LaunchImage@2x.png": (320, 320),
    "LaunchImage@3x.png": (480, 480),
}

# Android Density Configurations
ANDROID_LEGACY_DENSITIES: dict[str, int] = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ANDROID_ADAPTIVE_DENSITIES: dict[str, int] = {
    "drawable-mdpi": 108,
    "drawable-hdpi": 162,
    "drawable-xhdpi": 216,
    "drawable-xxhdpi": 324,
    "drawable-xxxhdpi": 432,
}

ANDROID_LAUNCH_IMAGE_DENSITIES: dict[str, int] = {
    "drawable-mdpi": 160,
    "drawable-hdpi": 240,
    "drawable-xhdpi": 320,
    "drawable-xxhdpi": 480,
    "drawable-xxxhdpi": 640,
}


class PreflightSecurityError(Exception):
    """Raised when an output path, XML configuration, or manifest entry violates security/containment."""


@dataclass(frozen=True)
class PlannedTarget:
    """Descriptor for a validated, approved output image target."""
    target_path: Path
    width: int
    height: int
    mode: str                    # "RGB" or "RGBA"
    category: str                # e.g., "android_legacy", "android_adaptive_fg", etc.
    safe_box: int
    generator_kind: str          # "legacy", "adaptive_fg", "adaptive_mono", "launch_img", "ios_icon", "ios_launch"


def compute_sha256(path: Path) -> str:
    """Compute SHA-256 hash of a file."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def is_reparse_or_link(path: Path) -> bool:
    """
    Check if a path is a symbolic link, directory junction, or reparse point.
    is_symlink() alone is insufficient on Windows because directory junctions
    (and mount points / reparse points) may not return True for is_symlink().
    Uses os.lstat() without following links.
    """
    try:
        if path.is_symlink():
            return True
        st = os.lstat(path)
        reparse_flag = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
        if getattr(st, "st_file_attributes", 0) & reparse_flag:
            return True
        try:
            os.readlink(path)
            return True
        except (OSError, ValueError, AttributeError, NotImplementedError):
            pass
    except (OSError, FileNotFoundError):
        pass
    return False


def validate_no_reparse_below_anchor(path: Path, anchor_root: Path) -> None:
    """
    Inspect every path component strictly BELOW anchor_root
    lexically (using os.lstat without resolving symlinks/junctions).
    If any component below anchor_root is a reparse point, directory junction,
    or symlink (including dangling links whose targets do not exist),
    raise PreflightSecurityError.
    Must be called BEFORE calling .resolve() on path or any ancestor.
    """
    try:
        rel = path.relative_to(anchor_root)
    except ValueError:
        raise PreflightSecurityError(f"Path '{path}' is not under anchor root '{anchor_root}'")

    if any(part in (".", "..") for part in rel.parts):
        raise PreflightSecurityError(f"Path relative sequence contains traversal: '{rel}'")

    curr = anchor_root
    for part in rel.parts:
        curr = curr / part
        if is_reparse_or_link(curr):
            raise PreflightSecurityError(
                f"Reparse point / junction / symlink detected below workspace root: {curr}"
            )


def get_strictly_anchored_root() -> Path:
    """
    Anchor strictly to script.parent.parent.resolve().
    Verifies script location, anchor directory, and absence of symlink escapes.
    Existing workspace root itself may be an ASCII junction, which is permitted as the trusted root.
    """
    script_path = Path(__file__).resolve()
    if script_path.parent.name != "tool":
        raise PreflightSecurityError(
            f"Script parent must be 'tool', found '{script_path.parent.name}'; rejected."
        )

    anchor_root = script_path.parent.parent.resolve()
    if not anchor_root.is_dir():
        raise PreflightSecurityError(f"Anchor root {anchor_root} is not an existing directory; rejected.")

    # Reject reparse points on the script path below anchor_root
    validate_no_reparse_below_anchor(anchor_root / "tool", anchor_root)
    validate_no_reparse_below_anchor(script_path, anchor_root)

    return anchor_root


def validate_path_containment(
    path: Path,
    expected_dir: Path,
    anchor_root: Path,
    plain_filename: str,
    master_logo_path: Path,
) -> Path:
    """
    Strict preflight path containment validator.
    - Rejects plain filenames containing path separators, '..', or trailing spaces.
    - Rejects reparse points, junctions, or symlinks on any existing component below anchor_root
      LEXICALLY BEFORE calling .resolve() on expected_dir or path.
    - Resolves expected_dir and path only after lexical validation passes.
    - Verifies both resolve strictly within anchor_root and target is inside expected_dir.
    - Verifies target path does not target the immutable master logo.
    """
    # 1. Plain filename validation
    if path.name != plain_filename:
        raise PreflightSecurityError(
            f"Target filename '{path.name}' does not match expected plain filename '{plain_filename}'"
        )

    if "/" in plain_filename or "\\" in plain_filename:
        raise PreflightSecurityError(f"Filename contains illegal path separators: '{plain_filename}'")

    if plain_filename in (".", "..") or ".." in plain_filename:
        raise PreflightSecurityError(f"Filename contains illegal traversal sequence: '{plain_filename}'")

    # 2. Lexical reparse check strictly BELOW anchor_root BEFORE calling .resolve()
    validate_no_reparse_below_anchor(expected_dir, anchor_root)
    validate_no_reparse_below_anchor(path, anchor_root)

    # 3. Canonical containment check (safe to resolve only after lexical validation passes)
    resolved_target = path.resolve()
    resolved_expected = expected_dir.resolve()
    resolved_anchor = anchor_root.resolve()

    try:
        resolved_target.relative_to(resolved_anchor)
    except ValueError:
        raise PreflightSecurityError(
            f"Resolved target path {resolved_target} escapes anchor root {resolved_anchor}"
        )

    try:
        resolved_expected.relative_to(resolved_anchor)
    except ValueError:
        raise PreflightSecurityError(
            f"Resolved expected directory {resolved_expected} escapes anchor root {resolved_anchor}"
        )

    try:
        resolved_target.relative_to(resolved_expected)
    except ValueError:
        raise PreflightSecurityError(
            f"Resolved target path {resolved_target} escapes expected directory {resolved_expected}"
        )

    # 4. Master logo collision check
    if resolved_target == master_logo_path.resolve():
        raise PreflightSecurityError(
            f"Target path {resolved_target} collides with master logo! Master logo is read-only."
        )

    return resolved_target


def preflight_ios_app_icons(
    appicon_dir: Path,
    anchor_root: Path,
    master_logo_path: Path,
) -> list[PlannedTarget]:
    """
    Preflight iOS AppIcon Contents.json entries requiring EXACT approved 19-tuple set.
    Rejects duplicate tuples, unsupported idioms/scales/sizes, and arbitrary extras,
    while permitting legitimate shared filenames between iPhone and iPad entries.
    Plans exactly 15 unique image targets matching APPROVED_IOS_APP_ICON_FILES.
    """
    contents_path = appicon_dir / "Contents.json"
    validate_no_reparse_below_anchor(contents_path, anchor_root)
    if not contents_path.is_file():
        raise PreflightSecurityError(f"AppIcon Contents.json missing at {contents_path}")

    # Canonical containment proof for contents_path
    try:
        contents_path.resolve().relative_to(anchor_root.resolve())
    except ValueError:
        raise PreflightSecurityError(f"AppIcon Contents.json escapes anchor root: {contents_path.resolve()}")

    try:
        with open(contents_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        raise PreflightSecurityError(f"AppIcon Contents.json is invalid JSON: {e}")

    images = data.get("images")
    if not isinstance(images, list) or len(images) == 0:
        raise PreflightSecurityError("AppIcon Contents.json 'images' array is missing or empty")

    if len(images) != len(APPROVED_IOS_APP_ICON_ENTRIES):
        raise PreflightSecurityError(
            f"AppIcon Contents.json entry count ({len(images)}) does not match expected {len(APPROVED_IOS_APP_ICON_ENTRIES)}"
        )

    seen_tuples: set[tuple[str, str, str, str]] = set()

    for idx, entry in enumerate(images):
        if not isinstance(entry, dict):
            raise PreflightSecurityError(f"Invalid entry at index {idx} in AppIcon Contents.json")

        filename = entry.get("filename")
        size_str = entry.get("size")
        scale_str = entry.get("scale")
        idiom = entry.get("idiom")

        if not all(isinstance(v, str) for v in (filename, size_str, scale_str, idiom)):
            raise PreflightSecurityError(f"Entry at index {idx} has missing or non-string attributes")

        if "/" in filename or "\\" in filename or ".." in filename:
            raise PreflightSecurityError(f"Entry filename contains separators or traversal: '{filename}'")

        if Path(filename).is_absolute():
            raise PreflightSecurityError(f"Entry filename is absolute: '{filename}'")

        entry_tuple = (filename, size_str, scale_str, idiom)

        if entry_tuple not in APPROVED_IOS_APP_ICON_ENTRIES:
            raise PreflightSecurityError(f"Unsupported AppIcon entry tuple at index {idx}: {entry_tuple}")

        if entry_tuple in seen_tuples:
            raise PreflightSecurityError(f"Duplicate AppIcon entry tuple detected at index {idx}: {entry_tuple}")

        seen_tuples.add(entry_tuple)

    if seen_tuples != APPROVED_IOS_APP_ICON_ENTRIES:
        missing = APPROVED_IOS_APP_ICON_ENTRIES - seen_tuples
        raise PreflightSecurityError(f"Contents.json missing approved AppIcon tuples: {missing}")

    # Plan the 15 unique output targets
    planned: list[PlannedTarget] = []
    for filename, (px_w, px_h) in APPROVED_IOS_APP_ICON_FILES.items():
        target_path = appicon_dir / filename
        validate_path_containment(
            path=target_path,
            expected_dir=appicon_dir,
            anchor_root=anchor_root,
            plain_filename=filename,
            master_logo_path=master_logo_path,
        )
        planned.append(PlannedTarget(
            target_path=target_path,
            width=px_w,
            height=px_h,
            mode="RGB",
            category="ios_app_icon",
            safe_box=int(round(px_w * 0.78)),
            generator_kind="ios_icon",
        ))

    return planned


def preflight_ios_launch_images(
    launch_dir: Path,
    anchor_root: Path,
    master_logo_path: Path,
) -> list[PlannedTarget]:
    """
    Preflight iOS LaunchImage Contents.json requiring EXACT approved 3-tuple set.
    Rejects arbitrary extras or wrong scale/idiom.
    """
    contents_path = launch_dir / "Contents.json"
    validate_no_reparse_below_anchor(contents_path, anchor_root)
    if not contents_path.is_file():
        raise PreflightSecurityError(f"LaunchImage Contents.json missing at {contents_path}")

    # Canonical containment proof for contents_path
    try:
        contents_path.resolve().relative_to(anchor_root.resolve())
    except ValueError:
        raise PreflightSecurityError(f"LaunchImage Contents.json escapes anchor root: {contents_path.resolve()}")

    try:
        with open(contents_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        raise PreflightSecurityError(f"LaunchImage Contents.json is invalid JSON: {e}")

    images = data.get("images")
    if not isinstance(images, list) or len(images) == 0:
        raise PreflightSecurityError("LaunchImage Contents.json 'images' array is missing or empty")

    if len(images) != len(APPROVED_IOS_LAUNCH_IMAGE_ENTRIES):
        raise PreflightSecurityError(
            f"LaunchImage entry count ({len(images)}) does not match expected {len(APPROVED_IOS_LAUNCH_IMAGE_ENTRIES)}"
        )

    seen_tuples: set[tuple[str, str, str]] = set()

    for idx, entry in enumerate(images):
        if not isinstance(entry, dict):
            raise PreflightSecurityError(f"Invalid entry at index {idx} in LaunchImage Contents.json")

        filename = entry.get("filename")
        scale_str = entry.get("scale")
        idiom = entry.get("idiom")

        if not all(isinstance(v, str) for v in (filename, scale_str, idiom)):
            raise PreflightSecurityError(f"LaunchImage entry at index {idx} has missing or non-string attributes")

        if "/" in filename or "\\" in filename or ".." in filename:
            raise PreflightSecurityError(f"LaunchImage filename contains illegal components: '{filename}'")

        if Path(filename).is_absolute():
            raise PreflightSecurityError(f"LaunchImage filename is absolute: '{filename}'")

        entry_tuple = (filename, scale_str, idiom)

        if entry_tuple not in APPROVED_IOS_LAUNCH_IMAGE_ENTRIES:
            raise PreflightSecurityError(f"Unsupported LaunchImage entry tuple: {entry_tuple}")

        if entry_tuple in seen_tuples:
            raise PreflightSecurityError(f"Duplicate LaunchImage entry tuple: {entry_tuple}")

        seen_tuples.add(entry_tuple)

    if seen_tuples != APPROVED_IOS_LAUNCH_IMAGE_ENTRIES:
        missing = APPROVED_IOS_LAUNCH_IMAGE_ENTRIES - seen_tuples
        raise PreflightSecurityError(f"Contents.json missing approved LaunchImage tuples: {missing}")

    planned = []
    for filename, (exp_w, exp_h) in APPROVED_IOS_LAUNCH_IMAGE_FILES.items():
        target_path = launch_dir / filename
        validate_path_containment(
            path=target_path,
            expected_dir=launch_dir,
            anchor_root=anchor_root,
            plain_filename=filename,
            master_logo_path=master_logo_path,
        )
        planned.append(PlannedTarget(
            target_path=target_path,
            width=exp_w,
            height=exp_h,
            mode="RGBA",
            category="ios_launch_image",
            safe_box=int(round(exp_w * 0.78)),
            generator_kind="ios_launch",
        ))

    return planned


def preflight_android_assets(
    res_dir: Path,
    anchor_root: Path,
    master_logo_path: Path,
) -> list[PlannedTarget]:
    """
    Preflight all Android fixed density paths for legacy, adaptive foreground,
    adaptive monochrome, and launch image assets.
    """
    planned = []

    # 1. Android Legacy Icons (48, 72, 96, 144, 192) - Opaque RGB
    for density, size in ANDROID_LEGACY_DENSITIES.items():
        expected_dir = res_dir / density
        target_path = expected_dir / "ic_launcher.png"
        validate_path_containment(
            path=target_path,
            expected_dir=expected_dir,
            anchor_root=anchor_root,
            plain_filename="ic_launcher.png",
            master_logo_path=master_logo_path,
        )
        planned.append(PlannedTarget(
            target_path=target_path,
            width=size,
            height=size,
            mode="RGB",
            category="android_legacy_icon",
            safe_box=int(round(size * 0.78)),
            generator_kind="legacy",
        ))

    # 2. Android Adaptive Foreground PNGs (108, 162, 216, 324, 432) - RGBA, 66dp safe zone
    for density, canvas_size in ANDROID_ADAPTIVE_DENSITIES.items():
        expected_dir = res_dir / density
        target_path = expected_dir / "ic_launcher_foreground.png"
        validate_path_containment(
            path=target_path,
            expected_dir=expected_dir,
            anchor_root=anchor_root,
            plain_filename="ic_launcher_foreground.png",
            master_logo_path=master_logo_path,
        )
        safe_box = int(round(canvas_size * (66.0 / 108.0)))
        planned.append(PlannedTarget(
            target_path=target_path,
            width=canvas_size,
            height=canvas_size,
            mode="RGBA",
            category="android_adaptive_foreground",
            safe_box=safe_box,
            generator_kind="adaptive_fg",
        ))

    # 3. Android Adaptive Monochrome Silhouettes (API 33) - RGBA
    for density, canvas_size in ANDROID_ADAPTIVE_DENSITIES.items():
        expected_dir = res_dir / density
        target_path = expected_dir / "ic_launcher_monochrome.png"
        validate_path_containment(
            path=target_path,
            expected_dir=expected_dir,
            anchor_root=anchor_root,
            plain_filename="ic_launcher_monochrome.png",
            master_logo_path=master_logo_path,
        )
        safe_box = int(round(canvas_size * (66.0 / 108.0)))
        planned.append(PlannedTarget(
            target_path=target_path,
            width=canvas_size,
            height=canvas_size,
            mode="RGBA",
            category="android_adaptive_monochrome",
            safe_box=safe_box,
            generator_kind="adaptive_mono",
        ))

    # 4. Android Launch Images across densities
    for density, canvas_size in ANDROID_LAUNCH_IMAGE_DENSITIES.items():
        expected_dir = res_dir / density
        target_path = expected_dir / "launch_image.png"
        validate_path_containment(
            path=target_path,
            expected_dir=expected_dir,
            anchor_root=anchor_root,
            plain_filename="launch_image.png",
            master_logo_path=master_logo_path,
        )
        safe_box = int(round(canvas_size * 0.72))
        planned.append(PlannedTarget(
            target_path=target_path,
            width=canvas_size,
            height=canvas_size,
            mode="RGBA",
            category="android_launch_image",
            safe_box=safe_box,
            generator_kind="launch_img",
        ))

    # Default fallback in drawable/ (320x320)
    drawable_dir = res_dir / "drawable"
    fallback_path = drawable_dir / "launch_image.png"
    validate_path_containment(
        path=fallback_path,
        expected_dir=drawable_dir,
        anchor_root=anchor_root,
        plain_filename="launch_image.png",
        master_logo_path=master_logo_path,
    )
    planned.append(PlannedTarget(
        target_path=fallback_path,
        width=320,
        height=320,
        mode="RGBA",
        category="android_launch_image_default",
        safe_box=int(round(320 * 0.72)),
        generator_kind="launch_img",
    ))

    return planned


def verify_xml_syntax(anchor_root: Path) -> tuple[list[dict], bool]:
    """
    Parse and validate all Android XML and iOS Storyboard configuration files.
    Returns (results, all_valid).
    Rejects any missing files, reparse points on ancestors below anchor_root, or XML parse errors.
    """
    xml_files = [
        anchor_root / "android/app/src/main/res/values/colors.xml",
        anchor_root / "android/app/src/main/res/values-night/colors.xml",
        anchor_root / "android/app/src/main/res/values/styles.xml",
        anchor_root / "android/app/src/main/res/values-night/styles.xml",
        anchor_root / "android/app/src/main/res/values-v31/styles.xml",
        anchor_root / "android/app/src/main/res/values-night-v31/styles.xml",
        anchor_root / "android/app/src/main/res/drawable/launch_background.xml",
        anchor_root / "android/app/src/main/res/drawable-v21/launch_background.xml",
        anchor_root / "android/app/src/main/res/drawable/ic_launcher_background.xml",
        anchor_root / "android/app/src/main/res/drawable/ic_splash_icon.xml",
        anchor_root / "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml",
        anchor_root / "android/app/src/main/res/mipmap-anydpi-v33/ic_launcher.xml",
        anchor_root / "ios/Runner/Base.lproj/LaunchScreen.storyboard",
    ]
    results = []
    all_valid = True
    for xml_path in xml_files:
        rel_path = str(xml_path.relative_to(anchor_root))
        try:
            validate_no_reparse_below_anchor(xml_path, anchor_root)
        except PreflightSecurityError as e:
            results.append({"path": rel_path, "exists": True, "valid": False, "error": str(e)})
            all_valid = False
            continue

        if not xml_path.is_file():
            results.append({"path": rel_path, "exists": False, "valid": False, "error": "File not found"})
            all_valid = False
            continue

        try:
            tree = ET.parse(xml_path)
            root_tag = tree.getroot().tag
            results.append({"path": rel_path, "exists": True, "valid": True, "root_tag": root_tag})
        except Exception as e:
            results.append({"path": rel_path, "exists": True, "valid": False, "error": str(e)})
            all_valid = False

    return results, all_valid


def preflight_all(anchor_root: Path) -> tuple[Path, list[PlannedTarget]]:
    """
    Run full containment, XML configuration, and security preflight BEFORE creating
    any directory or writing any file.
    All key paths retain exact lexical forms under canonical anchor_root.
    Validates absence of reparse points below anchor_root BEFORE calling .resolve().
    Returns (master_logo_path, planned_targets).
    If any check fails, PreflightSecurityError is raised and no modifications are made.
    """
    # 1. Master logo lexical validation (retain exact lexical path, check reparse BEFORE resolve)
    logo_path = anchor_root / "assets" / "branding" / "logo.png"
    validate_no_reparse_below_anchor(logo_path, anchor_root)
    if not logo_path.is_file():
        raise PreflightSecurityError(f"Master logo not found at {logo_path}")

    # Canonical containment proof for master logo
    try:
        logo_path.resolve().relative_to(anchor_root.resolve())
    except ValueError:
        raise PreflightSecurityError(f"Master logo resolved path escapes anchor root: {logo_path.resolve()}")

    # 2. Key directory anchors - retain EXACT lexical paths under anchor_root
    res_dir = anchor_root / "android" / "app" / "src" / "main" / "res"
    xcassets_dir = anchor_root / "ios" / "Runner" / "Assets.xcassets"
    appicon_dir = xcassets_dir / "AppIcon.appiconset"
    launch_dir = xcassets_dir / "LaunchImage.imageset"

    for d, desc in (
        (res_dir, "Android res directory"),
        (xcassets_dir, "iOS Assets.xcassets directory"),
        (appicon_dir, "AppIcon.appiconset directory"),
        (launch_dir, "LaunchImage.imageset directory"),
    ):
        validate_no_reparse_below_anchor(d, anchor_root)
        if not d.is_dir():
            raise PreflightSecurityError(f"{desc} missing at {d}")
        try:
            d.resolve().relative_to(anchor_root.resolve())
        except ValueError:
            raise PreflightSecurityError(f"{desc} resolved path escapes anchor root: {d}")

    # 3. XML Configuration Preflight: All 13 XMLs must exist and be valid
    _, xml_ok = verify_xml_syntax(anchor_root)
    if not xml_ok:
        raise PreflightSecurityError("Preflight failed: One or more XML configuration files are missing or malformed.")

    # 4. Gather preflighted targets
    all_targets: list[PlannedTarget] = []
    all_targets.extend(preflight_android_assets(res_dir, anchor_root, logo_path))
    all_targets.extend(preflight_ios_app_icons(appicon_dir, anchor_root, logo_path))
    all_targets.extend(preflight_ios_launch_images(launch_dir, anchor_root, logo_path))

    # 5. Check for duplicate target paths
    target_paths = set()
    for t in all_targets:
        if t.target_path in target_paths:
            raise PreflightSecurityError(f"Duplicate planned target path: {t.target_path}")
        target_paths.add(t.target_path)

    # Total must be exactly 39 files: 21 Android + 15 iOS AppIcon + 3 iOS LaunchImage
    if len(all_targets) != 39:
        raise PreflightSecurityError(
            f"Preflight planned target count ({len(all_targets)}) does not match expected 39 targets"
        )

    return logo_path, all_targets


def crop_to_content(image: Image.Image) -> Image.Image:
    """Crop image to non-zero alpha bounding box."""
    bbox = image.getbbox()
    if bbox is None:
        raise ValueError("Source image is empty (bounding box is None)")
    return image.crop(bbox)


def fit_and_center_art(
    art: Image.Image,
    target_box_size: int,
    canvas_size: int,
    background_mode: str = "RGBA",
    background_color: tuple[int, ...] = (0, 0, 0, 0),
) -> Image.Image:
    """
    Scale artwork to fit within target_box_size (preserving aspect ratio)
    and center it onto a canvas of size (canvas_size, canvas_size).
    """
    art_w, art_h = art.size
    scale = min(target_box_size / art_w, target_box_size / art_h)
    new_w = max(1, int(round(art_w * scale)))
    new_h = max(1, int(round(art_h * scale)))

    resized_art = art.resize((new_w, new_h), RESAMPLE_FILTER)

    canvas = Image.new(background_mode, (canvas_size, canvas_size), background_color)
    paste_x = (canvas_size - new_w) // 2
    paste_y = (canvas_size - new_h) // 2

    canvas.paste(resized_art, (paste_x, paste_y), resized_art)
    return canvas


def render_target_image(art: Image.Image, target: PlannedTarget) -> Image.Image:
    """Render the exact image for a preflighted target."""
    if target.generator_kind in ("legacy", "ios_icon"):
        # Opaque RGB forest green
        return fit_and_center_art(
            art=art,
            target_box_size=target.safe_box,
            canvas_size=target.width,
            background_mode="RGB",
            background_color=COLOR_FOREST_GREEN,
        )
    elif target.generator_kind in ("adaptive_fg", "launch_img", "ios_launch"):
        # Transparent RGBA
        return fit_and_center_art(
            art=art,
            target_box_size=target.safe_box,
            canvas_size=target.width,
            background_mode="RGBA",
            background_color=(0, 0, 0, 0),
        )
    elif target.generator_kind == "adaptive_mono":
        # API 33 themed silhouette from alpha mask
        fg = fit_and_center_art(
            art=art,
            target_box_size=target.safe_box,
            canvas_size=target.width,
            background_mode="RGBA",
            background_color=(0, 0, 0, 0),
        )
        alpha_channel = fg.getchannel("A")
        white_rgb = Image.new("RGB", (target.width, target.height), (255, 255, 255))
        return Image.merge("RGBA", (*white_rgb.split(), alpha_channel))
    else:
        raise ValueError(f"Unknown generator kind: {target.generator_kind}")


def run_verify_mode(anchor_root: Path, logo_path: Path, targets: list[PlannedTarget]) -> dict:
    """Run read-only verification on source logo, XML files, and existing output targets."""
    source_sha = compute_sha256(logo_path)
    xml_results, xml_ok = verify_xml_syntax(anchor_root)

    report: dict = {
        "status": "ok",
        "anchor_root": str(anchor_root),
        "source_logo": {
            "path": str(logo_path.relative_to(anchor_root)),
            "sha256": source_sha,
            "size_bytes": os.path.getsize(logo_path),
        },
        "xml_validation": xml_results,
        "xml_all_valid": xml_ok,
        "targets_checked": len(targets),
        "targets": [],
    }

    # Strict check: any XML failure immediately invalidates overall verification status
    if not xml_ok:
        report["status"] = "xml_validation_failed"

    try:
        with Image.open(logo_path) as src_img:
            report["source_logo"]["dimensions"] = list(src_img.size)
            report["source_logo"]["mode"] = src_img.mode
            bbox = src_img.convert("RGBA").getbbox()
            report["source_logo"]["content_bbox"] = list(bbox) if bbox else None
    except Exception as e:
        report["status"] = "error"
        report["source_logo"]["read_error"] = str(e)

    all_present = True
    for t in targets:
        p = t.target_path
        rel = str(p.relative_to(anchor_root))
        if not p.exists():
            all_present = False
            report["targets"].append({
                "path": rel,
                "exists": False,
                "expected_dim": [t.width, t.height],
                "expected_mode": t.mode,
            })
            continue

        try:
            with Image.open(p) as img:
                w, h = img.size
                mode = img.mode
                dim_valid = (w == t.width and h == t.height)
                mode_valid = (mode == t.mode)
                sha = compute_sha256(p)
                report["targets"].append({
                    "path": rel,
                    "exists": True,
                    "width": w,
                    "height": h,
                    "mode": mode,
                    "dim_valid": dim_valid,
                    "mode_valid": mode_valid,
                    "sha256": sha,
                })
                if not (dim_valid and mode_valid):
                    all_present = False
        except Exception as e:
            all_present = False
            report["targets"].append({"path": rel, "exists": True, "read_error": str(e)})

    if not all_present:
        if report["status"] == "ok":
            report["status"] = "pending_generation"
        else:
            report["status"] = "verification_failed"

    return report


def run_selfcheck(anchor_root: Path) -> bool:
    """
    Smallest meaningful self-check testing in-memory security invariants and XML files.
    Zero file writes, zero modifications.
    """
    # 1. Verify AppIcon approved entries and files
    if len(APPROVED_IOS_APP_ICON_ENTRIES) != 19:
        raise AssertionError(f"Expected 19 AppIcon tuples, found {len(APPROVED_IOS_APP_ICON_ENTRIES)}")
    if len(APPROVED_IOS_APP_ICON_FILES) != 15:
        raise AssertionError(f"Expected 15 AppIcon files, found {len(APPROVED_IOS_APP_ICON_FILES)}")

    tuple_filenames = {t[0] for t in APPROVED_IOS_APP_ICON_ENTRIES}
    if tuple_filenames != set(APPROVED_IOS_APP_ICON_FILES.keys()):
        raise AssertionError("AppIcon tuple filenames do not match approved files set")

    # 2. Verify LaunchImage approved entries and files
    if len(APPROVED_IOS_LAUNCH_IMAGE_ENTRIES) != 3:
        raise AssertionError(f"Expected 3 LaunchImage tuples, found {len(APPROVED_IOS_LAUNCH_IMAGE_ENTRIES)}")
    if len(APPROVED_IOS_LAUNCH_IMAGE_FILES) != 3:
        raise AssertionError(f"Expected 3 LaunchImage files, found {len(APPROVED_IOS_LAUNCH_IMAGE_FILES)}")

    # 3. Path containment test against dummy path (lexical before canonical)
    dummy_logo = anchor_root / "assets" / "branding" / "logo.png"
    test_dir = anchor_root / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    valid_target = test_dir / "Icon-App-20x20@1x.png"
    validated = validate_path_containment(valid_target, test_dir, anchor_root, "Icon-App-20x20@1x.png", dummy_logo)
    if validated != valid_target.resolve():
        raise AssertionError("Validation failed to return canonical target")

    # Test that traversal is rejected
    traversal_caught = False
    try:
        validate_path_containment(test_dir / ".." / "escape.png", test_dir, anchor_root, "escape.png", dummy_logo)
    except PreflightSecurityError:
        traversal_caught = True
    if not traversal_caught:
        raise AssertionError("Traversal check failed to reject '..'")

    # 4. XML syntax check across the 13 workspace XMLs
    _, xml_ok = verify_xml_syntax(anchor_root)
    if not xml_ok:
        raise AssertionError("XML syntax check failed on workspace configuration files")

    # 5. In-memory regression check: verify validate_no_reparse_below_anchor catches
    # simulated junctions on AppIcon.appiconset and assets/branding before any .resolve()
    orig_checker = globals()["is_reparse_or_link"]
    try:
        # Simulate AppIcon.appiconset is a junction
        globals()["is_reparse_or_link"] = lambda p: p.name == "AppIcon.appiconset"
        reparse_caught = False
        try:
            validate_no_reparse_below_anchor(test_dir, anchor_root)
        except PreflightSecurityError:
            reparse_caught = True
        if not reparse_caught:
            raise AssertionError("validate_no_reparse_below_anchor failed to reject simulated AppIcon junction")

        # Simulate branding is a junction for master logo
        test_logo_path = anchor_root / "assets" / "branding" / "logo.png"
        globals()["is_reparse_or_link"] = lambda p: p.name == "branding"
        logo_reparse_caught = False
        try:
            validate_no_reparse_below_anchor(test_logo_path, anchor_root)
        except PreflightSecurityError:
            logo_reparse_caught = True
        if not logo_reparse_caught:
            raise AssertionError("validate_no_reparse_below_anchor failed to reject simulated branding junction")

        # Simulate dangling symlink on a nonexistent target path below anchor_root
        nonexistent_target = test_dir / "nonexistent_dangling.png"
        globals()["is_reparse_or_link"] = lambda p: p.name == "nonexistent_dangling.png"
        dangling_caught = False
        try:
            validate_no_reparse_below_anchor(nonexistent_target, anchor_root)
        except PreflightSecurityError:
            dangling_caught = True
        if not dangling_caught:
            raise AssertionError("validate_no_reparse_below_anchor failed to reject simulated dangling symlink")
    finally:
        globals()["is_reparse_or_link"] = orig_checker

    return True


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Zad Alruh Platform Branding Export Generator (Strictly Anchored)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run strict preflight and report planned actions with TRUE ZERO WRITES (no mkdir, no files written)",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Read-only verification check of master logo, XML configurations, and output files",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit report in JSON format",
    )
    parser.add_argument(
        "--selfcheck",
        action="store_true",
        help="Run smallest meaningful internal invariant self-check of validation rules and XML configs",
    )

    args = parser.parse_args()

    # Step 1: Strict anchor root resolution (canonical root resolved once)
    try:
        anchor_root = get_strictly_anchored_root()
    except PreflightSecurityError as e:
        print(f"FATAL: Root anchor security violation: {e}", file=sys.stderr)
        sys.exit(2)

    # Mode: In-memory self-check
    if args.selfcheck:
        try:
            run_selfcheck(anchor_root)
            print("Self-check PASSED: all security invariants, tuples, and XML configurations verified.")
            sys.exit(0)
        except Exception as e:
            print(f"Self-check FAILED: {e}", file=sys.stderr)
            sys.exit(1)

    # Step 2: Strict preflight validation of all targets before any disk writes
    try:
        logo_path, planned_targets = preflight_all(anchor_root)
    except PreflightSecurityError as e:
        print(f"PREFLIGHT FAILED: {e}", file=sys.stderr)
        print("Preflight failure preserves all existing assets. Zero modifications made.", file=sys.stderr)
        sys.exit(3)

    # Mode: Read-only Verify
    if args.verify:
        report = run_verify_mode(anchor_root, logo_path, planned_targets)
        if args.json:
            print(json.dumps(report, indent=2))
        else:
            print("=== Branding Verification Report ===")
            print(f"Status:      {report['status']}")
            print(f"Master Logo: {report['source_logo'].get('path')}")
            print(f"Source SHA:  {report['source_logo'].get('sha256')}")
            print("\nXML Validation:")
            for x in report["xml_validation"]:
                valid_str = "OK" if x.get("valid") else f"FAIL ({x.get('error')})"
                print(f"  [{valid_str}] {x['path']}")
            print(f"\nTargets Checked: {report['targets_checked']}")
            missing = [item['path'] for item in report['targets'] if not item.get('exists')]
            if missing:
                print(f"  Missing files ({len(missing)}):")
                for m in missing[:5]:
                    print(f"    - {m}")
                if len(missing) > 5:
                    print(f"    ... and {len(missing) - 5} more")
            else:
                print("  All 39 targets verified on disk.")
        sys.exit(0 if report["status"] == "ok" else 1)

    # Mode: Dry-Run (True Zero Writes)
    if args.dry_run:
        summary = {
            "status": "dry_run_preflight_passed",
            "anchor_root": str(anchor_root),
            "master_logo": str(logo_path.relative_to(anchor_root)),
            "source_sha256": compute_sha256(logo_path),
            "total_planned_targets": len(planned_targets),
            "planned_targets": [
                {
                    "path": str(t.target_path.relative_to(anchor_root)),
                    "width": t.width,
                    "height": t.height,
                    "mode": t.mode,
                    "category": t.category,
                }
                for t in planned_targets
            ],
        }
        if args.json:
            print(json.dumps(summary, indent=2))
        else:
            print("=== Dry-Run Preflight Passed ===")
            print(f"Anchor Root:     {anchor_root}")
            print(f"Master Logo:     {logo_path.relative_to(anchor_root)}")
            print(f"Source SHA-256:  {summary['source_sha256']}")
            print(f"Planned Targets: {len(planned_targets)} (TRUE ZERO WRITES executed)")
            for t in planned_targets:
                print(f"  [PLAN] {t.width}x{t.height} ({t.mode}) -> {t.target_path.relative_to(anchor_root)}")
        sys.exit(0)

    # Mode: Deterministic Export Execution (Preflight Already Succeeded)
    source_sha = compute_sha256(logo_path)
    print(f"Anchor root: {anchor_root}")
    print(f"Loading master logo: {logo_path.relative_to(anchor_root)}")
    print(f"Master logo SHA-256: {source_sha}")

    with Image.open(logo_path) as raw_logo:
        logo_rgba = raw_logo.convert("RGBA")
        art = crop_to_content(logo_rgba)

    manifest = []
    print(f"\nPreflight passed. Intentionally writing {len(planned_targets)} approved icons...")

    for target in planned_targets:
        # Create parent directory only after full preflight passed
        target.target_path.parent.mkdir(parents=True, exist_ok=True)
        img = render_target_image(art, target)
        img.save(target.target_path, format="PNG", optimize=True)

        manifest.append({
            "target": str(target.target_path.relative_to(anchor_root)),
            "width": target.width,
            "height": target.height,
            "mode": target.mode,
            "category": target.category,
            "sha256": compute_sha256(target.target_path),
        })

    summary = {
        "status": "success",
        "anchor_root": str(anchor_root),
        "source_sha256": source_sha,
        "total_targets_written": len(manifest),
        "manifest": manifest,
    }

    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print(f"\nBranding export completed: {len(manifest)} approved icons written.")
        print(f"Master logo preserved unchanged. SHA-256: {source_sha}")


if __name__ == "__main__":
    main()
