#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$repo_dir/dist/LidSwitch.app"

cd "$repo_dir"
swift build -c "$configuration" --product LidSwitch
swift build -c "$configuration" --product LidSwitchHelper

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Library/LaunchServices"
cp ".build/$configuration/LidSwitch" "$app_dir/Contents/MacOS/LidSwitch"
cp ".build/$configuration/LidSwitchHelper" "$app_dir/Contents/Library/LaunchServices/LidSwitchHelper"
cp "Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --identifier me.dapi.LidSwitch.Helper --sign - "$app_dir/Contents/Library/LaunchServices/LidSwitchHelper"
codesign --force --sign - "$app_dir"

echo "$app_dir"
