#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
app_dir="$repo_dir/dist/LidSwitch.app"
evidence_dir="$repo_dir/dist/notarization"
signing_identity="${LIDSWITCH_CODESIGN_IDENTITY:-}"
notary_profile="${LIDSWITCH_NOTARY_PROFILE:-}"
notary_timeout="${LIDSWITCH_NOTARY_TIMEOUT:-30m}"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

[[ -n "$signing_identity" && "$signing_identity" != "-" ]] || {
    print -u2 "Set LIDSWITCH_CODESIGN_IDENTITY to a Developer ID Application identity"
    exit 2
}
[[ -n "$notary_profile" ]] || {
    print -u2 "Set LIDSWITCH_NOTARY_PROFILE to a notarytool Keychain profile name"
    exit 2
}

identity_line="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -F "$signing_identity" | /usr/bin/head -n 1 || true)"
[[ -n "$identity_line" && "$identity_line" == *"Developer ID Application:"* ]] || {
    print -u2 "The requested Developer ID Application identity is unavailable"
    exit 2
}

notarytool_path="$(xcrun --find notarytool 2>/dev/null || true)"
stapler_path="$(xcrun --find stapler 2>/dev/null || true)"
[[ -x "$notarytool_path" ]] || {
    print -u2 "notarytool is unavailable"
    exit 2
}
[[ -x "$stapler_path" ]] || {
    print -u2 "stapler is unavailable; install full Xcode"
    exit 2
}

# Validate the profile without printing credential or submission history data.
xcrun notarytool history --keychain-profile "$notary_profile" \
    --output-format plist >/dev/null

LIDSWITCH_CODESIGN_IDENTITY="$signing_identity" \
    "$repo_dir/Scripts/build-app.sh" release

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_dir"
signature_details="$(/usr/bin/codesign -dvvv "$app_dir" 2>&1)"
[[ "$signature_details" == *"Authority=Developer ID Application:"* ]]
[[ "$signature_details" == *"(runtime)"* ]]

temporary_dir="$(mktemp -d /tmp/lidswitch-notarization.XXXXXX)"
trap 'rm -rf "$temporary_dir"' EXIT
submission_archive="$temporary_dir/LidSwitch.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$submission_archive"

mkdir -p "$evidence_dir"
submission_plist="$evidence_dir/submission.plist"
if ! xcrun notarytool submit "$submission_archive" \
    --keychain-profile "$notary_profile" \
    --wait \
    --timeout "$notary_timeout" \
    --output-format plist >"$submission_plist"; then
    print -u2 "Notarization failed; response saved to $submission_plist"
    exit 1
fi

notary_status=$(/usr/libexec/PlistBuddy -c 'Print :status' "$submission_plist")
[[ "$notary_status" == "Accepted" ]] || {
    submission_id=$(/usr/libexec/PlistBuddy -c 'Print :id' "$submission_plist" 2>/dev/null || true)
    if [[ -n "$submission_id" ]]; then
        xcrun notarytool log "$submission_id" \
            --keychain-profile "$notary_profile" \
            "$evidence_dir/notary-log.json" || true
    fi
    print -u2 "Notarization status is $notary_status; response: $submission_plist"
    exit 1
}

xcrun stapler staple "$app_dir"
xcrun stapler validate "$app_dir"
/usr/sbin/spctl --assess --type execute --verbose=4 "$app_dir"
"$repo_dir/Scripts/archive-app.sh"

print "PASS: Developer ID signature, hardened runtime, notarization, staple, Gatekeeper assessment, and final archive"
print "Notary evidence: $submission_plist"
