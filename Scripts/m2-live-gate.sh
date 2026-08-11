#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
action="${1:-preflight}"
confirmation="${2:-}"
app_dir="${LIDSWITCH_LIVE_APP_PATH:-/Applications/LidSwitch.app}"
app_executable="$app_dir/Contents/MacOS/LidSwitch"
daemon_executable="$app_dir/Contents/MacOS/LidSwitchDaemon"
probe_executable="$repo_dir/.build/release/LidSwitchUnauthorizedProbe"
legacy_helper="/Library/PrivilegedHelperTools/me.dapi.LidSwitch.Helper"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

team_identifier() {
    /usr/bin/codesign -dvvv "$1" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p'
}

preflight() {
    [[ "$app_dir" == /Applications/* ]] || {
        print -u2 "LIDSWITCH_LIVE_APP_PATH must point inside /Applications"
        exit 2
    }
    [[ -x "$app_executable" && -x "$daemon_executable" ]] || {
        print -u2 "A notarized LidSwitch.app is not installed at $app_dir"
        exit 2
    }
    [[ -x "$probe_executable" ]] || {
        print -u2 "Release unauthorized probe is missing; run the signed release build first"
        exit 2
    }

    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_dir"
    /usr/bin/codesign -R='identifier "me.dapi.LidSwitch"' --verify "$app_dir"
    /usr/bin/codesign -R='identifier "me.dapi.LidSwitch.Daemon"' --verify "$daemon_executable"
    /usr/bin/codesign -R='identifier "me.dapi.LidSwitch.UnauthorizedProbe"' --verify "$probe_executable"

    app_team="$(team_identifier "$app_dir")"
    [[ -n "$app_team" && "$app_team" != "not set" ]] || {
        print -u2 "The installed app has no production Team ID"
        exit 2
    }
    [[ "$(team_identifier "$daemon_executable")" == "$app_team" ]]
    [[ "$(team_identifier "$probe_executable")" == "$app_team" ]]

    xcrun stapler validate "$app_dir"
    /usr/sbin/spctl --assess --type execute --verbose=4 "$app_dir"
    print "PASS: notarized live artifacts; Team ID $app_team"
    "$app_executable" --m2-daemon-status
}

require_confirmation() {
    [[ "$confirmation" == "--confirm-system-changes" ]] || {
        print -u2 "This action changes Service Management state. Re-run with --confirm-system-changes"
        exit 2
    }
}

case "$action" in
    preflight)
        preflight
        ;;
    register)
        require_confirmation
        preflight
        "$app_executable" --m2-register
        status_output="$("$app_executable" --m2-daemon-status)"
        print "$status_output"
        if [[ "$status_output" == Requires\ approval* ]]; then
            "$app_executable" --m2-open-approval-settings
            print "Approve LidSwitch in System Settings > General > Login Items, then run:"
            print "  Scripts/m2-live-gate.sh verify"
            exit 3
        fi
        ;;
    verify)
        preflight
        status_output="$("$app_executable" --m2-daemon-status)"
        [[ "$status_output" == Enabled* ]] || {
            print -u2 "M2 daemon is not enabled: $status_output"
            exit 1
        }
        version_output="$("$app_executable" --m2-check-version)"
        [[ "$version_output" == "m2-spike-v1;euid=0" ]] || {
            print -u2 "Unexpected authorized reply: $version_output"
            exit 1
        }
        "$probe_executable"
        print "PASS: enabled, authorized client received root reply, wrong-identifier client rejected"
        ;;
    unregister)
        require_confirmation
        preflight
        legacy_checksum=""
        if [[ -f "$legacy_helper" ]]; then
            legacy_checksum="$(/usr/bin/shasum -a 256 "$legacy_helper")"
        fi
        "$app_executable" --m2-unregister
        status_output="$("$app_executable" --m2-daemon-status)"
        [[ "$status_output" == Not\ registered* ]] || {
            print -u2 "Unexpected status after unregister: $status_output"
            exit 1
        }
        if [[ -n "$legacy_checksum" ]]; then
            [[ -f "$legacy_helper" ]]
            [[ "$(/usr/bin/shasum -a 256 "$legacy_helper")" == "$legacy_checksum" ]]
        fi
        print "PASS: M2 daemon unregistered"
        ;;
    *)
        print -u2 "Usage: $0 {preflight|register|verify|unregister} [--confirm-system-changes]"
        exit 2
        ;;
esac
