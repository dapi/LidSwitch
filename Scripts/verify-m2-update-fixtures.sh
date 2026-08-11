#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-debug}"
app_dir="$repo_dir/dist/LidSwitch.app"
app_executable="$app_dir/Contents/MacOS/LidSwitch"
daemon_executable="$app_dir/Contents/MacOS/LidSwitchDaemon"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

build_fixture() {
    local variant="$1"
    LIDSWITCH_M2_PROTOCOL_VARIANT="$variant" \
        "$repo_dir/Scripts/build-app.sh" "$configuration" >/dev/null
    /usr/bin/codesign --verify --deep --strict "$app_dir"
    "$app_executable" --m2-protocol-version
    /usr/bin/shasum -a 256 "$daemon_executable" | /usr/bin/awk '{print $1}'
}

v1_result="$(build_fixture v1)"
v1_version="${v1_result%%$'\n'*}"
v1_hash="${v1_result##*$'\n'}"
[[ "$v1_version" == "m2-spike-v1" ]]

v2_result="$(build_fixture v2)"
v2_version="${v2_result%%$'\n'*}"
v2_hash="${v2_result##*$'\n'}"
[[ "$v2_version" == "m2-spike-v2" ]]
[[ "$v1_hash" != "$v2_hash" ]]

# Leave the normal development artifact in the default v1 state.
LIDSWITCH_M2_PROTOCOL_VARIANT=v1 \
    "$repo_dir/Scripts/build-app.sh" "$configuration" >/dev/null

print "PASS: deterministic M2 update fixtures"
print "v1: $v1_version daemon-sha256=$v1_hash"
print "v2: $v2_version daemon-sha256=$v2_hash"
