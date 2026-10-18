#!/usr/bin/env python3
"""Verify signed Android artifacts and native alignment without exposing local keys."""
import argparse
import hashlib
import json
import re
import struct
import subprocess
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path


def command(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def verify_elf(data: bytes, name: str) -> None:
    assert data[:4] == b"\x7fELF", f"Not an ELF library: {name}"
    endian = "<" if data[5] == 1 else ">"
    is_64 = data[4] == 2
    offset = struct.unpack_from(endian + ("Q" if is_64 else "I"), data, 32 if is_64 else 28)[0]
    entry_size, count = struct.unpack_from(endian + "HH", data, 54 if is_64 else 42)
    for index in range(count):
        position = offset + index * entry_size
        kind = struct.unpack_from(endian + "I", data, position)[0]
        if kind != 1:
            continue
        alignment = struct.unpack_from(endian + ("Q" if is_64 else "I"), data, position + (48 if is_64 else 28))[0]
        assert alignment >= 16384, f"ELF load alignment below 16 KB: {name} ({alignment})"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundletool", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    android = root / "android"
    gradle = (android / "app/build.gradle.kts").read_text()
    properties = dict(line.split("=", 1) for line in (android / "local.properties").read_text().splitlines() if "=" in line)
    package = re.search(r'applicationId = "([^"]+)"', gradle).group(1)
    version_name = re.search(r'versionName = "([^\"]+)"', gradle).group(1)
    version = int(re.search(r"versionCode = (\d+)", gradle).group(1))
    target_sdk = int(re.search(r"targetSdk = (\d+)", gradle).group(1))
    tools = Path(properties["sdk.dir"]) / "build-tools/36.0.0"
    apk = android / "app/build/outputs/apk/release/app-release.apk"
    bundle = android / "app/build/outputs/bundle/release/app-release.aab"
    command(str(tools / "apksigner"), "verify", "--verbose", str(apk))
    signing = command("jarsigner", "-verify", str(bundle))
    assert "jar verified" in signing, "AAB signature was not verified"
    command(str(tools / "zipalign"), "-c", "-P", "16", "-v", "4", str(apk))
    command("java", "-jar", str(args.bundletool), "validate", f"--bundle={bundle}")
    manifest = command("java", "-jar", str(args.bundletool), "dump", "manifest", f"--bundle={bundle}")
    assert f'package="{package}"' in manifest
    assert f'android:versionName="{version_name}"' in manifest
    assert f'android:versionCode="{version}"' in manifest
    assert f'android:targetSdkVersion="{target_sdk}"' in manifest
    manifest_root = ET.fromstring(manifest)
    android_name = "{http://schemas.android.com/apk/res/android}name"
    permissions = sorted(item.attrib[android_name] for item in manifest_root.findall("uses-permission"))
    assert not any(name.startswith("android.permission.health.WRITE_") for name in permissions), "Health access must be read-only"
    assert "com.google.android.gms.permission.AD_ID" not in permissions, "Advertising identifiers are not needed"
    configuration = json.loads(command("java", "-jar", str(args.bundletool), "dump", "config", f"--bundle={bundle}"))
    native = []
    has_play_key = False
    for archive in [apk, bundle]:
        with zipfile.ZipFile(archive) as zipped:
            for item in zipped.infolist():
                if item.filename.endswith(".so"):
                    verify_elf(zipped.read(item), item.filename)
                    if archive == bundle:
                        native.append(item.filename)
                if archive == apk and item.filename.endswith(".dex"):
                    data = zipped.read(item)
                    has_play_key |= properties["REVENUECAT_PLAY_KEY"].encode() in data
                    test_key = properties.get("REVENUECAT_TEST_KEY", "")
                    assert not test_key or test_key.encode() not in data, "Test Store key leaked into release"
                    for marker in [b"seedScreenshotData", b"skipOnboarding", b"forcePro", b"fixture-"]:
                        assert marker not in data, f"Debug launch hook leaked into release: {marker!r}"
    assert has_play_key, "Production Play key is missing from release"
    if native:
        assert "PAGE_ALIGNMENT_16K" in json.dumps(configuration), "Bundle does not request 16 KB ZIP alignment"
    report = {"package": package, "versionName": version_name, "versionCode": version, "targetSdk": target_sdk, "nativeLibraries": len(native), "permissions": permissions, "alignment": "16 KB ZIP and ELF verified", "signature": "APK and AAB verified", "artifacts": {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [apk, bundle]}}
    destination = android / "app/build/release-verification.json"
    destination.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
