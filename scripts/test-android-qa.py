#!/usr/bin/env python3
"""Verify optimized QA on Recharge's owned temporary Pro AVD, without billing."""
import re
import shlex
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOST = "jackwallner@192.168.4.25"
SERIAL = "emulator-5582"
REMOTE = "/Users/jackwallner/tmp/sol-recharge"
ADB = "/Users/jackwallner/Library/Android/sdk/platform-tools/adb"
PACKAGE = re.search(r'applicationId = "([^"]+)"', (ROOT / "android/app/build.gradle.kts").read_text()).group(1)
PROOF = ROOT / "android/verification/final"


def remote(*arguments: str) -> bytes:
    result = subprocess.run(["ssh", HOST, shlex.join(arguments)], check=True, capture_output=True)
    return result.stdout


def adb(*arguments: str) -> bytes:
    return remote(ADB, "-s", SERIAL, *arguments)


def nodes() -> list:
    adb("shell", "uiautomator", "dump", "/sdcard/sol-recharge-window.xml")
    return list(ET.fromstring(adb("shell", "cat", "/sdcard/sol-recharge-window.xml")).iter("node"))


def wait_text(text: str) -> ET.Element:
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        for node in nodes():
            if node.get("text") == text:
                return node
        time.sleep(1)
    raise AssertionError(f"UI text did not appear: {text}")


def click(text: str) -> None:
    node = wait_text(text)
    assert node.get("enabled") == "true", f"Disabled control: {text}"
    left, top, right, bottom = map(int, re.findall(r"\d+", node.get("bounds")))
    adb("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))
    print(f"QA: {text}", flush=True)


def capture(name: str) -> None:
    (PROOF / name).write_bytes(adb("exec-out", "screencap", "-p"))


def main() -> None:
    name = adb("emu", "avd", "name").decode().splitlines()[0]
    assert name == "sol-recharge", "Refusing to change another AVD"
    apk = ROOT / "android/app/build/outputs/apk/qa/app-qa.apk"
    assert apk.is_file(), "Build assembleQa first"
    PROOF.mkdir(parents=True, exist_ok=True)
    subprocess.run(["scp", str(apk), f"{HOST}:{REMOTE}/app-qa.apk"], check=True)
    # The debug and QA keys differ by build host. Only this disposable AVD's
    # Recharge installation is removed before switching signatures.
    adb("uninstall", PACKAGE)
    adb("install", "-r", f"{REMOTE}/app-qa.apk")
    adb("logcat", "-c")
    adb("shell", "am", "start", "-W", "-n", f"{PACKAGE}/.MainActivity",
        "--ez", "forcePro", "true", "--ez", "seedScreenshotData", "true",
        "--ez", "skipOnboarding", "true", "--ei", "tab", "2")
    wait_text("Recovery time,\nfrom your workouts")
    capture("qa-welcome.png")
    print("QA: all debug bypass extras ignored", flush=True)
    click("Continue")
    wait_text("Recharge reads\nHealth Connect")
    click("Continue")
    time.sleep(2)
    adb("shell", "input", "keyevent", "4")
    for _ in range(4):
        click("Skip this one")
    click("I understand")
    click("Get Started")
    time.sleep(2)
    adb("shell", "input", "keyevent", "4")
    wait_text("No recent workout")
    assert not any(node.get("text") == "Recharge+ active" for node in nodes())
    capture("qa-today.png")
    errors = adb("logcat", "-d", "-s", "AndroidRuntime:E").decode()
    assert "FATAL EXCEPTION" not in errors, "QA crashed; inspect the owned AVD log"
    print("Optimized QA: release hooks absent, free onboarding complete, no fabricated workout, no crash", flush=True)


if __name__ == "__main__":
    main()
