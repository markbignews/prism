#!/usr/bin/env python3
"""Build/run Prism with real SDK metadata, without probing from Package.swift."""
import argparse
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "swift version"


def selected_sdk():
    try:
        sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"], text=True).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise SystemExit("Cannot query macOS SDK. Select Xcode/CLT with SDK 26+ using xcode-select or DEVELOPER_DIR.") from error
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", sdk) or int(sdk.split(".")[0]) < 26:
        raise SystemExit("Building native glass APIs requires macOS SDK 26 or newer; no SDK version is fabricated.")
    return sdk


def swift_command(sdk, configuration="release", arch="arm64", run=False):
    command = ["swift", "run" if run else "build", "--package-path", str(PACKAGE), "-c", configuration, "--arch", arch]
    if os.environ.get("PRISM_DISABLE_MANIFEST_SANDBOX") == "1":
        command += ["--disable-sandbox"]
    command += ["-Xswiftc", "-warnings-as-errors"]
    for value in ["-platform_version", "macos", "15.0", sdk]:
        command += ["-Xlinker", value]
    return command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-c", "--configuration", choices=["debug", "release"], default="release")
    parser.add_argument("--arch", choices=["arm64"], default="arm64")
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    command = swift_command(selected_sdk(), args.configuration, args.arch, args.run)
    if args.run:
        command += ["Prism"]
    subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
