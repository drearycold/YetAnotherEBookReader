#!/usr/bin/env bash
# Picks the simulator CI tests on: the newest iOS runtime the SDK supports, and on it "iPhone 17"
# (the name used in AGENTS.md), else its first iPhone. Picking by UDID keeps the name and the
# runtime together. Writes DESTINATION and SIMULATOR_UDID to $GITHUB_ENV.
set -euo pipefail

SDK=$(xcrun --sdk iphonesimulator --show-sdk-version)
PICK=$(xcrun simctl list devices available -j | jq -r --arg sdk "$SDK" '
  def ver: split(".") | map(tonumber);
  [.devices | to_entries[]
    | select(.key | test("SimRuntime\\.iOS-"))
    | (.key | capture("iOS-(?<v>[0-9-]+)$").v | gsub("-"; ".")) as $os
    | select(($os | ver) <= ($sdk | ver))
    | .value[] | select(.name | startswith("iPhone"))
    | {udid, os: $os, name}]
  | (map(.os | ver) | max) as $newest
  | map(select((.os | ver) == $newest))
  | ((map(select(.name == "iPhone 17")) + .)[0] // empty)
  | "\(.udid) \(.os) \(.name)"')
if [ -z "$PICK" ]; then
  echo "No iPhone simulator available for the iOS $SDK SDK" >&2
  exit 1
fi
read -r UDID OS NAME <<< "$PICK"
echo "Using simulator: $NAME (iOS $OS, $UDID)"
echo "DESTINATION=platform=iOS Simulator,id=$UDID" >> "$GITHUB_ENV"
echo "SIMULATOR_UDID=$UDID" >> "$GITHUB_ENV"
