#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
release_dir="$repo_dir/dist/release"
app_dir="$repo_dir/dist/LidSwitch.app"
plist="$repo_dir/Resources/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
archive_name="LidSwitch-${version}-macos-arm64.zip"
archive_path="$release_dir/$archive_name"

[[ -d "$app_dir" ]] || {
    print -u2 "LidSwitch.app is missing; run Scripts/build-app.sh first"
    exit 1
}

rm -rf "$release_dir"
mkdir -p "$release_dir"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive_path"

cd "$release_dir"
/usr/bin/shasum -a 256 "$archive_name" > "$archive_name.sha256"

print "$archive_path"
print "$archive_path.sha256"
