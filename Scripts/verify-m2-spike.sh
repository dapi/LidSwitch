#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-debug}"
app_dir="$repo_dir/dist/LidSwitch.app"
daemon_plist="$app_dir/Contents/Library/LaunchDaemons/me.dapi.LidSwitch.Daemon.plist"

"$repo_dir/Scripts/build-app.sh" "$configuration" >/dev/null
swift build --package-path "$repo_dir" -c "$configuration" \
    --product LidSwitchCoreChecks >/dev/null

/usr/bin/plutil -lint "$daemon_plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$daemon_plist")" == "me.dapi.LidSwitch.Daemon" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$daemon_plist")" == "Contents/MacOS/LidSwitchDaemon" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :MachServices:me.dapi.LidSwitch.Daemon.XPC' "$daemon_plist")" == "true" ]]

[[ -x "$app_dir/Contents/MacOS/LidSwitch" ]]
[[ -x "$app_dir/Contents/MacOS/LidSwitchDaemon" ]]
[[ -x "$app_dir/Contents/Library/LaunchServices/LidSwitchHelper" ]]

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_dir"
/usr/bin/codesign -R='identifier "me.dapi.LidSwitch.Daemon"' \
    --verify "$app_dir/Contents/MacOS/LidSwitchDaemon"
/usr/bin/codesign -R='identifier "me.dapi.LidSwitch"' \
    --verify "$app_dir"
/usr/bin/codesign -R='identifier "me.dapi.LidSwitch.UnauthorizedProbe"' \
    --verify "$repo_dir/.build/$configuration/LidSwitchUnauthorizedProbe"
if /usr/bin/codesign -R='identifier "me.dapi.LidSwitch"' \
    --verify "$repo_dir/.build/$configuration/LidSwitchUnauthorizedProbe" 2>/dev/null; then
    print -u2 "FAIL: unauthorized probe unexpectedly satisfies the app identifier requirement"
    exit 1
fi

team_identifier() {
    /usr/bin/codesign -dvvv "$1" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p'
}

app_team="$(team_identifier "$app_dir")"
if [[ "$app_team" != "not set" ]]; then
    [[ -n "$app_team" ]]
    [[ "$(team_identifier "$app_dir/Contents/MacOS/LidSwitchDaemon")" == "$app_team" ]]
    [[ "$(team_identifier "$repo_dir/.build/$configuration/LidSwitchUnauthorizedProbe")" == "$app_team" ]]
fi

status_output="$($app_dir/Contents/MacOS/LidSwitch --m2-daemon-status)"
[[ "$status_output" == *"auth:"* ]]

"$repo_dir/.build/$configuration/LidSwitchCoreChecks"

print "PASS: M2 bundle layout, launchd plist, signatures, peer identity checks, status path, and existing core checks"
print "Status: $status_output"
if [[ "$status_output" == *"ad-hoc development build"* ]]; then
    print "NOTE: live registration and production peer authentication still require a notarized Developer ID build"
fi
