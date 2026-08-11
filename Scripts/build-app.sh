#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$repo_dir/dist/LidSwitch.app"
signing_identity="${LIDSWITCH_CODESIGN_IDENTITY:--}"
codesign_args=(--force --sign "$signing_identity")

if [[ "$signing_identity" != "-" ]]; then
    codesign_args+=(--timestamp --options runtime)
fi

cd "$repo_dir"
swift build -c "$configuration" --product LidSwitch
swift build -c "$configuration" --product LidSwitchHelper
swift build -c "$configuration" --product LidSwitchDaemon
swift build -c "$configuration" --product LidSwitchUnauthorizedProbe

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Library/LaunchServices"
mkdir -p "$app_dir/Contents/Library/LaunchDaemons"
cp ".build/$configuration/LidSwitch" "$app_dir/Contents/MacOS/LidSwitch"
cp ".build/$configuration/LidSwitchHelper" "$app_dir/Contents/Library/LaunchServices/LidSwitchHelper"
cp ".build/$configuration/LidSwitchDaemon" "$app_dir/Contents/MacOS/LidSwitchDaemon"
cp "Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "Resources/me.dapi.LidSwitch.Daemon.plist" "$app_dir/Contents/Library/LaunchDaemons/me.dapi.LidSwitch.Daemon.plist"

# Sign each nested executable before sealing the containing app. A real
# Developer ID identity can be supplied for the notarized lifecycle test:
# LIDSWITCH_CODESIGN_IDENTITY="Developer ID Application: …" ./Scripts/build-app.sh
codesign "${codesign_args[@]}" \
    --identifier me.dapi.LidSwitch.Helper \
    "$app_dir/Contents/Library/LaunchServices/LidSwitchHelper"
codesign "${codesign_args[@]}" \
    --identifier me.dapi.LidSwitch.Daemon \
    "$app_dir/Contents/MacOS/LidSwitchDaemon"
codesign "${codesign_args[@]}" \
    --identifier me.dapi.LidSwitch.UnauthorizedProbe \
    "$repo_dir/.build/$configuration/LidSwitchUnauthorizedProbe"
codesign "${codesign_args[@]}" "$app_dir"

echo "$app_dir"
