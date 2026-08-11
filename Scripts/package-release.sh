#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
release_dir="$repo_dir/dist/release"
plist="$repo_dir/Resources/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
archive_name="LidSwitch-${version}-macos-arm64.zip"
archive_path="$release_dir/$archive_name"

"$repo_dir/Scripts/build-app.sh" release

rm -rf "$release_dir"
mkdir -p "$release_dir"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
    "$repo_dir/dist/LidSwitch.app" \
    "$archive_path"

cd "$release_dir"
/usr/bin/shasum -a 256 "$archive_name" > "$archive_name.sha256"

echo "$archive_path"
echo "$archive_path.sha256"
