#!/usr/bin/env python3
"""Build a source-identifiable arm64 macOS app; optional Developer ID/notarization."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from uuid import uuid4
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_app import selected_sdk, swift_command

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "swift version"


def source_digest():
    # Covers shipped application/build inputs; Tests and docs intentionally do
    # not affect the binary-source identity. This is not a whole-repo digest.
    paths = [ROOT / "VERSION", PACKAGE / "Package.swift", Path(__file__).resolve(), ROOT / "scripts/build_app.py"]
    paths += [p for directory in [PACKAGE / "Sources", PACKAGE / "Resources"] for p in directory.rglob("*") if p.is_file() and p.name != ".DS_Store"]
    digest = hashlib.sha256()
    for path in sorted(paths, key=lambda p: p.relative_to(ROOT).as_posix()):
        digest.update(path.relative_to(ROOT).as_posix().encode() + b"\0")
        digest.update(path.read_bytes() + b"\0")
    return digest.hexdigest()


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def install_bundle(source, destination, backup_root):
    """Install an already verified bundle without merging, with durable rollback."""
    destination = destination.expanduser().resolve()
    if destination.suffix != ".app":
        raise ValueError("Application destination must end in .app")
    destination.parent.mkdir(parents=True, exist_ok=True)
    old_version = "unknown"
    if destination.exists():
        info_path = destination / "Contents/Info.plist"
        if not info_path.is_file():
            raise ValueError("Refusing to replace a destination without an app Info.plist")
        with info_path.open("rb") as file:
            old_info = plistlib.load(file)
        if old_info.get("CFBundleIdentifier") != "com.prism.chatclient":
            raise ValueError("Refusing to replace a different application")
        old_version = old_info.get("CFBundleShortVersionString", "unknown")
    with tempfile.TemporaryDirectory(prefix="prism-install-", dir=destination.parent) as stage:
        incoming = Path(stage) / destination.name
        shutil.copytree(source, incoming)
        backup = None
        if destination.exists():
            backup_root = backup_root.expanduser().resolve()
            backup_root.mkdir(parents=True, exist_ok=True)
            stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            backup = backup_root / (destination.stem + "-" + old_version + "-" + stamp + "-" + uuid4().hex[:8] + ".app")
            shutil.move(str(destination), backup)
        try:
            shutil.move(str(incoming), destination)
        except Exception:
            if backup is not None:
                shutil.move(str(backup), destination)
            raise
        if backup is not None:
            print("Previous app preserved at:", backup)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=PACKAGE / "Prism.app")
    parser.add_argument("--sync-release", action="store_true", help="Also install the identical verified bundle into Prism/release")
    parser.add_argument("--backup-dir", type=Path, default=Path.home() / "Documents/Prism-build-backups", help="Durable backup directory outside the repository")
    parser.add_argument("--identity", default="-", help="Developer ID identity; default is ad hoc")
    parser.add_argument("--notary-profile", help="Existing notarytool Keychain profile; requires Developer ID")
    parser.add_argument("--digest", action="store_true", help="Print the deterministic source digest only")
    args = parser.parse_args()
    if args.digest:
        print(source_digest())
        return
    if args.notary_profile and args.identity == "-":
        parser.error("--notary-profile requires a Developer ID --identity")
    version = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        parser.error("VERSION must contain major.minor.patch")
    sdk = selected_sdk()
    swift = swift_command(sdk)
    digest_before = source_digest()
    run(*swift)
    if source_digest() != digest_before:
        parser.error("Source files changed while building; run the package command again")
    binary_dir = Path(subprocess.check_output(swift + ["--show-bin-path"], text=True).strip())
    binary = binary_dir / "Prism"
    if not binary.is_file():
        parser.error("Release executable is missing after a successful build; inspect the SwiftPM output path")
    architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).strip()
    if architectures != "arm64":
        parser.error("Expected an arm64 release executable, got: " + architectures)
    load_commands = subprocess.check_output(["otool", "-l", str(binary)], text=True)
    build_version = re.search(r"cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform \d+\s+minos (\S+)\s+sdk (\S+)", load_commands)
    if not build_version or build_version.group(1) != "15.0" or build_version.group(2) != sdk:
        parser.error("Executable deployment target/SDK does not match macOS 15 and the selected SDK")
    destination = args.output.expanduser().resolve()
    if destination.suffix != ".app":
        parser.error("--output must end in .app")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="prism-package-", dir=destination.parent) as stage:
        app = Path(stage) / "Prism.app"
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Resources").mkdir()
        shutil.copy2(binary, contents / "MacOS/prism")
        shutil.copy2(PACKAGE / "Resources/Prism.icns", contents / "Resources/Prism.icns")
        info = dict(CFBundleDevelopmentRegion="en", CFBundleDisplayName="Prism", CFBundleName="Prism",
                    CFBundleExecutable="prism", CFBundleIdentifier="com.prism.chatclient", CFBundlePackageType="APPL",
                    CFBundleIconFile="Prism.icns", CFBundleInfoDictionaryVersion="6.0", LSMinimumSystemVersion="15.0",
                    CFBundleShortVersionString=version, CFBundleVersion=version, NSHighResolutionCapable=True,
                    PrismBuildSourceDigest=source_digest())
        with (contents / "Info.plist").open("wb") as file:
            plistlib.dump(info, file)
        options = [] if args.identity == "-" else ["--options", "runtime", "--timestamp"]
        run("codesign", "--force", "--sign", args.identity, *options, app)
        run("codesign", "--verify", "--deep", "--strict", app)
        if args.notary_profile:
            archive = Path(stage) / "Prism.zip"
            run("ditto", "-c", "-k", "--keepParent", app, archive)
            run("xcrun", "notarytool", "submit", archive, "--keychain-profile", args.notary_profile, "--wait")
            run("xcrun", "stapler", "staple", app)
            run("xcrun", "stapler", "validate", app)
        install_bundle(app, destination, args.backup_dir)
        run("codesign", "--verify", "--deep", "--strict", destination)
        if args.sync_release:
            distributable = ROOT / "release/Prism-SwiftUI-macOS.app"
            if distributable.resolve() != destination:
                install_bundle(destination, distributable, args.backup_dir)
            run("codesign", "--verify", "--deep", "--strict", distributable)
            for relative in ["Contents/MacOS/prism", "Contents/Resources/Prism.icns", "Contents/Info.plist", "Contents/_CodeSignature/CodeResources"]:
                if (destination / relative).read_bytes() != (distributable / relative).read_bytes():
                    parser.error("Formal/distributable bundle mismatch: " + relative)
            print("Distributable:", distributable)
    print("App:", destination)
    print("Version:", version, "Source SHA-256:", source_digest())
    print("Signing:", "ad hoc; not notarized" if args.identity == "-" else "Developer ID" + ("; notarized" if args.notary_profile else "; not notarized"))


if __name__ == "__main__":
    main()
