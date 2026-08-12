#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-debug}"
app_dir="$repo_dir/dist/LidSwitch.app"

"$repo_dir/Scripts/build-app.sh" "$configuration" >/dev/null
/usr/bin/codesign --verify --deep --strict "$app_dir"
version="$($app_dir/Contents/MacOS/LidSwitch --m2-protocol-version)"
[[ "$version" == "managed-lid-v1" ]]

print "PASS: managed-lid protocol fixture"
print "version: $version"
