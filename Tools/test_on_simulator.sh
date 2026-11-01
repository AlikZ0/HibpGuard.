#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# A concrete simulator UUID is selected from the installed runtimes.
xcodebuild -version
hibp_simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime, entries in sorted(devices.items(), reverse=True):
    if "iOS" not in runtime:
        continue
    for device in entries:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
sys.exit("No available iPhone simulator. Install an iOS runtime in Xcode Settings > Components.")
')"

xcodebuild test \
  -project HibpGuard.xcodeproj \
  -scheme HibpGuard \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${hibp_simulator_id}" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "build/Tests-$(date -u +%Y%m%dT%H%M%SZ).xcresult"
