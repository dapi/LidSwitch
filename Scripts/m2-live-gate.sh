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
evidence_dir="$repo_dir/dist/m2-live-evidence"
evidence_tag="${LIDSWITCH_M2_EVIDENCE_TAG:-$(/bin/date -u '+%Y%m%dT%H%M%SZ')-$action}"
update_id="${LIDSWITCH_M2_UPDATE_ID:-default}"
update_state_dir="$evidence_dir/update-$update_id-baseline"

if [[ -z "$evidence_tag" || "$evidence_tag" == *[!A-Za-z0-9._-]* \
    || -z "$update_id" || "$update_id" == *[!A-Za-z0-9._-]* ]]; then
    print -u2 "Evidence tag and update ID may contain only letters, digits, dot, underscore, and hyphen"
    exit 2
fi

mkdir -p "$evidence_dir"
evidence_file="$evidence_dir/$evidence_tag.log"
[[ ! -e "$evidence_file" ]] || {
    print -u2 "Evidence file already exists: $evidence_file"
    exit 2
}
exec > >(/usr/bin/tee "$evidence_file") 2>&1

print "M2 live gate evidence v1"
print "action=$action"
print "timestamp=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
print "boot=$(/usr/sbin/sysctl -n kern.boottime)"
print "macOS=$(/usr/bin/sw_vers -productVersion) ($(/usr/bin/sw_vers -buildVersion))"
print "repository_commit=$(git -C "$repo_dir" rev-parse HEAD)"
print "app_path=$app_dir"
print "evidence_file=$evidence_file"

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
    print "app_protocol_version=$("$app_executable" --m2-protocol-version)"
    print "daemon_sha256=$(/usr/bin/shasum -a 256 "$daemon_executable" | /usr/bin/awk '{print $1}')"
    /usr/bin/codesign -dvvv "$daemon_executable" 2>&1 \
        | /usr/bin/grep -E '^(Identifier|TeamIdentifier|CDHash)='
    print "PASS: notarized live artifacts; Team ID $app_team"
    "$app_executable" --m2-daemon-status
}

verify_daemon() {
    status_output="$("$app_executable" --m2-daemon-status)"
    [[ "$status_output" == Enabled* ]] || {
        print -u2 "M2 daemon is not enabled: $status_output"
        exit 1
    }
    built_version="$("$app_executable" --m2-protocol-version)"
    expected_version="${LIDSWITCH_M2_EXPECTED_VERSION:-$built_version}"
    version_output="$("$app_executable" --m2-check-version)"
    [[ "$version_output" == "$expected_version;euid=0" ]] || {
        print -u2 "Unexpected authorized reply: $version_output; expected $expected_version;euid=0"
        exit 1
    }
    "$probe_executable"
    print "authorized_reply=$version_output"
    print "PASS: enabled, authorized client received root reply, wrong-identifier client rejected"
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
        verify_daemon
        ;;
    snapshot-update-baseline)
        preflight
        verify_daemon
        [[ ! -e "$update_state_dir" ]] || {
            print -u2 "Update baseline already exists; choose another LIDSWITCH_M2_UPDATE_ID"
            exit 2
        }
        mkdir -p "$update_state_dir"
        "$app_executable" --m2-protocol-version >"$update_state_dir/protocol-version"
        /usr/bin/shasum -a 256 "$daemon_executable" \
            | /usr/bin/awk '{print $1}' >"$update_state_dir/daemon-sha256"
        print "PASS: update baseline recorded in $update_state_dir"
        ;;
    verify-update)
        preflight
        [[ -f "$update_state_dir/protocol-version" && -f "$update_state_dir/daemon-sha256" ]] || {
            print -u2 "Update baseline is missing; run snapshot-update-baseline on v1 first"
            exit 2
        }
        baseline_version="$(<"$update_state_dir/protocol-version")"
        baseline_hash="$(<"$update_state_dir/daemon-sha256")"
        current_version="$("$app_executable" --m2-protocol-version)"
        current_hash="$(/usr/bin/shasum -a 256 "$daemon_executable" | /usr/bin/awk '{print $1}')"
        [[ "$current_version" != "$baseline_version" ]] || {
            print -u2 "Protocol version did not change: $current_version"
            exit 1
        }
        [[ "$current_hash" != "$baseline_hash" ]] || {
            print -u2 "Daemon executable hash did not change"
            exit 1
        }
        print "baseline_protocol_version=$baseline_version"
        print "baseline_daemon_sha256=$baseline_hash"
        verify_daemon
        print "PASS: updated daemon version and executable are active after re-registration"
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
        print -u2 "Usage: $0 {preflight|register|verify|snapshot-update-baseline|verify-update|unregister} [--confirm-system-changes]"
        exit 2
        ;;
esac
