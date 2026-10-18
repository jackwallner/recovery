#!/usr/bin/env python3
"""Capture real free-tier screens from the owned Pro AVD after QA verification."""
import re
import shlex
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOST = "jackwallner@192.168.4.25"
SERIAL = "emulator-5582"
ADB = "/Users/jackwallner/Library/Android/sdk/platform-tools/adb"
REMOTE = "/Users/jackwallner/tmp/sol-recharge"
PACKAGE = re.search(r'applicationId = "([^"]+)"', (ROOT / "android/app/build.gradle.kts").read_text()).group(1)
PROOF = ROOT / "android/verification/final"


def adb(*arguments: str) -> bytes:
    return subprocess.run(["ssh", HOST, shlex.join([ADB, "-s", SERIAL, *arguments])],
                          check=True, capture_output=True).stdout


def nodes() -> list:
    adb("shell", "uiautomator", "dump", "/sdcard/sol-recharge-capture.xml")
    return list(ET.fromstring(adb("shell", "cat", "/sdcard/sol-recharge-capture.xml")).iter("node"))


def wait_for(text: str, exact: bool = True) -> ET.Element:
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        for node in nodes():
            value = node.get("text", "")
            if value == text or (not exact and value.startswith(text)):
                return node
        time.sleep(1)
    raise AssertionError(f"Screen did not settle on {text}")


def capture(name: str) -> None:
    time.sleep(1)
    (PROOF / name).write_bytes(adb("exec-out", "screencap", "-p"))
    print(f"Captured {name}", flush=True)


def launch(tab: int = 0, scene: str = "recovering", dark: bool = False) -> None:
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-W", "-f", "0x10008000", "-n", f"{PACKAGE}/.MainActivity",
        "--ez", "uiTest", "true", "--ez", "skipOnboarding", "true",
        "--ez", "seedScreenshotData", "true", "--es", "scene", scene,
        "--es", "appearance", "dark" if dark else "light", "--ei", "tab", str(tab))


def main() -> None:
    assert adb("emu", "avd", "name").decode().splitlines()[0] == "sol-recharge"
    PROOF.mkdir(parents=True, exist_ok=True)
    apk = ROOT / "android/app/build/outputs/apk/debug/app-debug.apk"
    subprocess.run(["scp", str(apk), f"{HOST}:{REMOTE}/app-debug-final.apk"], check=True)
    adb("uninstall", PACKAGE)
    adb("install", "-r", f"{REMOTE}/app-debug-final.apk")
    adb("shell", "wm", "size", "720x1440")
    adb("shell", "settings", "put", "global", "sysui_demo_allowed", "1")
    for arguments in [
        ["command", "enter"], ["command", "clock", "hhmm", "0941"],
        ["command", "notifications", "visible", "false"],
        ["command", "network", "wifi", "show", "level", "4", "fully", "true", "mobile", "hide", "nosim", "hide"],
        ["command", "battery", "level", "100", "plugged", "false"],
    ]:
        extras = [item for pair in zip(arguments[::2], arguments[1::2]) for item in ("--es", *pair)]
        adb("shell", "am", "broadcast", "-a", "com.android.systemui.demo", *extras)
    # Settle the denied-access state against the actual empty Health Connect store.
    adb("shell", "pm", "grant", PACKAGE, "android.permission.health.READ_EXERCISE")
    adb("shell", "am", "start", "-W", "-f", "0x10008000", "-n", f"{PACKAGE}/.MainActivity",
        "--ez", "uiTest", "true", "--ez", "skipOnboarding", "true")
    wait_for("No recent workout")
    wait_for("Updated just now")
    time.sleep(1)
    launch()
    wait_for("left")
    capture("today-light.png")
    launch(scene="ready")
    wait_for("Ready")
    capture("ready-light.png")
    launch(tab=1)
    node = wait_for("Run", exact=False)
    capture("history-light.png")
    bounds = list(map(int, re.findall(r"\d+", node.get("bounds"))))
    adb("shell", "input", "tap", str((bounds[0] + bounds[2]) // 2), str((bounds[1] + bounds[3]) // 2))
    wait_for("Why")
    capture("detail-light.png")
    launch(dark=True)
    wait_for("left")
    capture("today-dark.png")
    launch(tab=2)
    wait_for("Personalized recovery from your history.")
    # Give the Test Store network request time to finish before reviewing plans.
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if any(node.get("text", "").startswith("Yearly") for node in nodes()):
            break
        adb("shell", "input", "swipe", "360", "850", "360", "350", "350")
        time.sleep(1)
    assert any(node.get("text", "").startswith("Yearly") for node in nodes()), "Test Store plans did not load"
    capture("test-store-plans.png")
    print("Free screens captured at native 720x1440. Test Store prices are verification only.", flush=True)


if __name__ == "__main__":
    main()
