#!/usr/bin/env python3
"""Capture real debug screens on the emulator host (jmbp or jmbp2) itself.

Usage: ANDROID_SERIAL=emulator-5580 EXPECTED_AVD=agent-emu-1 \
       python3 scripts/capture-android-host.py OUTPUT_DIR

Runs local adb against one leased AVD, installs the debug APK and walks the
free tier, Recharge+ (debug forcePro), the effort prompt, onboarding and the
Test Store plans. Debug launch options only; the release build ignores them.
"""
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERIAL = os.environ["ANDROID_SERIAL"]
EXPECTED_AVD = os.environ["EXPECTED_AVD"]
ADB = str(Path.home() / "Library/Android/sdk/platform-tools/adb")
PACKAGE = re.search(r'applicationId = "([^"]+)"', (ROOT / "android/app/build.gradle.kts").read_text()).group(1)
APK = ROOT / "android/app/build/outputs/apk/debug/app-debug.apk"


def adb(*arguments: str) -> bytes:
    return subprocess.run([ADB, "-s", SERIAL, *arguments], check=True, capture_output=True,
                          stdin=subprocess.DEVNULL).stdout


def nodes() -> list:
    adb("shell", "uiautomator", "dump", "/sdcard/recharge-capture.xml")
    return list(ET.fromstring(adb("shell", "cat", "/sdcard/recharge-capture.xml")).iter("node"))


def find(text: str, exact: bool = True):
    for node in nodes():
        value = node.get("text", "") or node.get("content-desc", "")
        if value == text or (not exact and value.startswith(text)):
            return node
    return None


def wait_for(text: str, exact: bool = True, timeout: float = 60) -> ET.Element:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        node = find(text, exact)
        if node is not None:
            return node
        time.sleep(1)
    raise AssertionError(f"Screen did not settle on {text}")


def tap(node: ET.Element) -> None:
    left, top, right, bottom = map(int, re.findall(r"\d+", node.get("bounds")))
    adb("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))


def settle(timeout: float = 20) -> None:
    """Wait until two consecutive dumps match, so a rescore is not caught mid-flight."""
    deadline = time.monotonic() + timeout
    previous = None
    while time.monotonic() < deadline:
        current = [(node.get("text"), node.get("bounds")) for node in nodes()]
        if current == previous:
            return
        previous = current
        time.sleep(1.5)


def capture(output: Path, name: str) -> None:
    settle()
    (output / name).write_bytes(adb("exec-out", "screencap", "-p"))
    print(f"Captured {name}", flush=True)


def launch(tab: int = 0, scene: str = "recovering", dark: bool = False, pro: bool = False,
           onboarding: bool = False, seed: bool = True) -> None:
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-W", "-f", "0x10008000", "-n", f"{PACKAGE}/.MainActivity",
        "--ez", "uiTest", "true", "--ez", "skipOnboarding", "false" if onboarding else "true",
        "--ez", "seedScreenshotData", "true" if seed else "false", "--es", "scene", scene,
        "--ez", "forcePro", "true" if pro else "false",
        "--es", "appearance", "dark" if dark else "light", "--ei", "tab", str(tab))


def demo_status_bar() -> None:
    adb("shell", "settings", "put", "global", "sysui_demo_allowed", "1")
    for arguments in [
        ["command", "enter"], ["command", "clock", "hhmm", "0941"],
        ["command", "notifications", "visible", "false"],
        ["command", "network", "wifi", "show", "level", "4", "fully", "true", "mobile", "hide", "nosim", "hide"],
        ["command", "battery", "level", "100", "plugged", "false"],
    ]:
        extras = [item for pair in zip(arguments[::2], arguments[1::2]) for item in ("--es", *pair)]
        adb("shell", "am", "broadcast", "-a", "com.android.systemui.demo", *extras)


def main() -> None:
    output = Path(sys.argv[1]).expanduser()
    output.mkdir(parents=True, exist_ok=True)
    assert adb("emu", "avd", "name").decode().splitlines()[0].strip() == EXPECTED_AVD
    adb("install", "-r", str(APK))
    adb("shell", "pm", "clear", PACKAGE)
    demo_status_bar()

    launch(onboarding=True, seed=False)
    wait_for("", exact=False)
    capture(output, "onboarding-light.png")

    # Seeded scenes need core access; settle it against the real empty store first.
    adb("shell", "pm", "grant", PACKAGE, "android.permission.health.READ_EXERCISE")
    launch(seed=False)
    wait_for("No recent workout")
    wait_for("Updated just now")
    launch()
    wait_for("left")
    capture(output, "today-free-light.png")
    launch(scene="ready")
    wait_for("Ready")
    capture(output, "ready-free-light.png")
    launch(tab=1)
    node = wait_for("Run", exact=False)
    capture(output, "history-free-light.png")
    tap(node)
    wait_for("Why", exact=False)
    capture(output, "detail-free-light.png")
    launch(scene="effort")
    wait_for("How hard was your", exact=False)
    capture(output, "effort-free-light.png")
    launch(dark=True)
    wait_for("left")
    capture(output, "today-free-dark.png")

    launch(tab=2)
    wait_for("Personalized recovery from your history.")
    capture(output, "upgrade-free-light.png")
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline and find("Yearly", exact=False) is None:
        adb("shell", "input", "swipe", "540", "1700", "540", "700", "350")
        time.sleep(1)
    assert find("Yearly", exact=False) is not None, "Test Store plans did not load"
    capture(output, "test-store-plans-light.png")

    launch(pro=True)
    wait_for("left")
    capture(output, "today-plus-light.png")
    launch(pro=True, tab=2)
    wait_for("Recharge+", exact=False)
    capture(output, "plus-tab-light.png")
    launch(pro=True, dark=True, tab=1)
    node = wait_for("Run", exact=False)
    capture(output, "history-plus-dark.png")
    tap(node)
    wait_for("Why", exact=False)
    capture(output, "detail-plus-dark.png")
    adb("shell", "am", "broadcast", "-a", "com.android.systemui.demo", "--es", "command", "exit")
    print(f"Captured debug screens from {EXPECTED_AVD} ({SERIAL}) into {output}", flush=True)


if __name__ == "__main__":
    main()
