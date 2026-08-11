#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$repo_dir/dist/LidSwitch.app"

cd "$repo_dir"
swift build -c "$configuration" --product LidSwitch

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
cp ".build/$configuration/LidSwitch" "$app_dir/Contents/MacOS/LidSwitch"
cp "Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"

echo "$app_dir"
