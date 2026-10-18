#!/usr/bin/env python3
"""Export expected analysis values from the iOS implementation without an iOS runtime."""
import os
import subprocess
import tempfile
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="recharge-parity-") as temporary:
        directory = Path(temporary)
        main_file = directory / "main.swift"
        main_file.write_text((root / "scripts/export-android-parity.swift").read_text())
        paywall = (root / "Recharge/Views/PaywallView.swift").read_text()
        features = directory / "ProFeature.swift"
        features.write_text(paywall[paywall.index("enum ProFeature:"):paywall.index("struct PaywallView:")])
        files = [root / "Shared/Utilities" / f"{name}.swift" for name in [
            "SessionLoadCalculator", "RecoveryCalculator", "RecoveryBaseline", "ObservedRecoveryPattern",
            "PersonalRecoveryModel", "AthleteProfile", "WorkoutClassifier", "CountdownFormat",
            "RechargeConversionCopy", "DateHelpers", "WhatsNew",
        ]]
        files += [root / "Shared/Models/RecoveryModels.swift", root / "RechargeTests/AthleteMatrix.swift", root / "RechargeTests/RecoveryFixtures.swift"]
        files.append(features)
        binary = directory / "parity"
        subprocess.run(["swiftc", *map(str, files), str(main_file), "-o", str(binary)], check=True)
        target = root / "android/app/src/test/resources/swift-parity.json"
        production = root / "android/app/src/main/resources/workout-classification.json"
        subprocess.run([str(binary), str(target), str(production)], check=True, env={**os.environ, "TZ": "UTC"})


if __name__ == "__main__":
    main()
