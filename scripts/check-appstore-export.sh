#!/bin/zsh

set -euo pipefail

submission_mode="false"
if [[ "${1:-}" == "--submission" ]]; then
    submission_mode="true"
    shift
fi

export_path="${1:-}"
if [[ -z "${export_path}" || -n "${2:-}" ]]; then
    print -u2 "Usage: ${0:t} [--submission] /path/to/AppStoreExport"
    exit 64
fi

script_dir="${0:A:h}"

fail() {
    print -u2 "App Store export check failed: $1"
    exit 2
}

[[ -d "${export_path}" ]] \
    || fail "export directory does not exist: ${export_path}"

packages=("${export_path}"/*.pkg(N))
(( ${#packages[@]} == 1 )) \
    || fail "expected exactly one exported .pkg, found ${#packages[@]}"
package_path="${packages[1]}"

if ! signature_details="$(
    /usr/sbin/pkgutil --check-signature "${package_path}" 2>&1
)"; then
    fail "pkgutil rejected the installer package signature"
fi
[[ "${signature_details}" == *"BUUH229D5Q"* ]] \
    || fail "the installer signature has the wrong Team ID"
[[ "${signature_details}" == \
    *"3rd Party Mac Developer Installer: Chenchen Xu (BUUH229D5Q)"* ]] \
    || fail "the installer package does not use the expected Apple Installer identity"
[[ "${signature_details:l}" != *"no signature"* ]] \
    || fail "the installer package is unsigned"

payload_files="$(/usr/sbin/pkgutil --payload-files "${package_path}")" \
    || fail "the installer package Payload cannot be read"

for expected_path in \
    'QuotaView.app/Contents/MacOS/QuotaView' \
    'QuotaView.app/Contents/PlugIns/QuotaViewWidgetExtension.appex' \
    'QuotaView.app/Contents/Resources/PrivacyInfo.xcprivacy'; do
    [[ "${payload_files}" == *"${expected_path}"* ]] \
        || fail "the Payload is missing ${expected_path}"
done

if print -r -- "${payload_files}" | /usr/bin/grep -Eiq \
    '\.storekit($|/)|\.xctest($|/)|ActivityHook|CodexAppServer|QuotaViewProbe|Runtime|Sparkle'; then
    fail "the Payload contains a forbidden test, Runtime, Helper, or updater item"
fi

temporary_root="${TMPDIR:-/private/tmp}"
if [[ ! -d "${temporary_root}" ]]; then
    temporary_root="/private/tmp"
fi
audit_directory="$(
    /usr/bin/mktemp -d \
        "${temporary_root%/}/QuotaView-appstore-export-check.XXXXXX"
)" || fail "could not create a temporary Payload audit directory"

cleanup() {
    if [[ -n "${audit_directory:-}" \
        && -d "${audit_directory}" \
        && "${audit_directory:t}" == QuotaView-appstore-export-check.* ]]; then
        /bin/rm -rf -- "${audit_directory}"
    fi
}
trap cleanup EXIT HUP INT TERM

expanded_path="${audit_directory}/expanded"
payload_root="${audit_directory}/payload"
/usr/sbin/pkgutil --expand "${package_path}" "${expanded_path}" \
    || fail "the installer package could not be expanded"

component_packages=("${expanded_path}"/*.pkg(N))
(( ${#component_packages[@]} == 1 )) \
    || fail \
        "expected exactly one component package, found ${#component_packages[@]}"
payload_archive="${component_packages[1]}/Payload"
[[ -f "${payload_archive}" ]] \
    || fail "the component package does not contain a Payload archive"

/bin/mkdir "${payload_root}" \
    || fail "the Payload extraction directory could not be created"
# `ditto` is required here: raw cpio extraction leaves AppleDouble metadata as
# `._*` files, which makes an otherwise valid framework appear to contain
# unsealed root files during codesign verification.
/usr/bin/ditto -x -z "${payload_archive}" "${payload_root}" \
    || fail "the component Payload could not be extracted"

payload_app="${payload_root}/QuotaView.app"
[[ -d "${payload_app}" ]] \
    || fail "the extracted Payload does not contain QuotaView.app"
appledouble_artifact="$(
    /usr/bin/find "${payload_app}" -name '._*' -print -quit
)"
[[ -z "${appledouble_artifact}" ]] \
    || fail "Payload extraction left an AppleDouble artifact: ${appledouble_artifact}"

bundle_check_mode="--signed"
if [[ "${submission_mode}" == "true" ]]; then
    bundle_check_mode="--submission"
fi
"${script_dir}/check-appstore-bundle.sh" \
    "${bundle_check_mode}" \
    "${payload_app}" \
    || fail "the extracted App bundle failed its ${bundle_check_mode} audit"

payload_widget="${payload_app}/Contents/PlugIns/QuotaViewWidgetExtension.appex"
payload_framework="${payload_app}/Contents/Frameworks/QuotaViewCore.framework"
for signed_item in \
    "${payload_app}" \
    "${payload_widget}" \
    "${payload_framework}"; do
    item_signature="$(
        /usr/bin/codesign -dv --verbose=4 "${signed_item}" 2>&1
    )" || fail "could not read a Payload code signature: ${signed_item}"
    [[ "${item_signature}" == \
        *"Authority=Apple Distribution: Chenchen Xu (BUUH229D5Q)"* ]] \
        || fail "Payload item is not Apple Distribution signed: ${signed_item}"
    [[ "${item_signature}" == *"TeamIdentifier=BUUH229D5Q"* ]] \
        || fail "Payload item has the wrong TeamIdentifier: ${signed_item}"
done

payload_executables=(
    "${payload_app}/Contents/MacOS/QuotaView"
    "${payload_widget}/Contents/MacOS/QuotaViewWidgetExtension"
    "${payload_framework}/Versions/A/QuotaViewCore"
)
discovered_executables=("${(@f)$(
    /usr/bin/find "${payload_app}" -type f -perm +111 -print
)}")
(( ${#discovered_executables[@]} == ${#payload_executables[@]} )) \
    || fail \
        "the Payload contains an unexpected number of executable files: ${#discovered_executables[@]}"
for executable_file in "${discovered_executables[@]}"; do
    case "${executable_file}" in
        "${payload_executables[1]}"|\
        "${payload_executables[2]}"|\
        "${payload_executables[3]}")
            ;;
        *)
            fail "the Payload contains an unexpected executable: ${executable_file}"
            ;;
    esac
done

for executable_file in "${payload_executables[@]}"; do
    dependency_dump="$(/usr/bin/otool -L "${executable_file}")" \
        || fail "could not inspect dynamic libraries: ${executable_file}"
    unexpected_dependency="$(
        print -r -- "${dependency_dump}" | /usr/bin/awk '
            /^\t/ {
                dependency = $1
                if (dependency ~ /^\/System\/Library\/Frameworks\// \
                    || dependency ~ /^\/usr\/lib\// \
                    || dependency == \
                        "@rpath/QuotaViewCore.framework/Versions/A/QuotaViewCore") {
                    next
                }
                print dependency
                exit
            }
        '
    )"
    [[ -z "${unexpected_dependency}" ]] \
        || fail \
            "Payload executable links an unexpected library: ${unexpected_dependency}"
done

embedded_profile="${payload_app}/Contents/embedded.provisionprofile"
[[ -f "${embedded_profile}" ]] \
    || fail "the Payload App does not embed a provisioning profile"
profile_plist="${audit_directory}/embedded-profile.plist"
/usr/bin/security cms \
    -D \
    -i "${embedded_profile}" \
    -o "${profile_plist}" \
    || fail "the embedded provisioning profile could not be decoded"

profile_name="$(
    /usr/bin/plutil -extract Name raw -o - "${profile_plist}"
)" || fail "the embedded profile has no name"
[[ "${profile_name}" == \
    "Mac Team Store Provisioning Profile: com.quotaview.menubar" ]] \
    || fail "unexpected embedded profile: ${profile_name}"
profile_uuid="$(
    /usr/bin/plutil -extract UUID raw -o - "${profile_plist}"
)" || fail "the embedded profile has no UUID"
profile_expiration="$(
    /usr/bin/plutil -extract ExpirationDate raw -o - "${profile_plist}"
)" || fail "the embedded profile has no expiration date"
profile_team="$(
    /usr/bin/plutil -extract TeamIdentifier.0 raw -o - "${profile_plist}"
)" || fail "the embedded profile has no TeamIdentifier"
[[ "${profile_team}" == "BUUH229D5Q" ]] \
    || fail "the embedded profile has the wrong TeamIdentifier"
profile_app_identifier="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :Entitlements:com.apple.application-identifier' \
        "${profile_plist}"
)" || fail "the embedded profile has no application identifier"
[[ "${profile_app_identifier}" == \
    "BUUH229D5Q.com.quotaview.menubar" ]] \
    || fail "the embedded profile has the wrong application identifier"
profile_app_groups="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :Entitlements:com.apple.security.application-groups' \
        "${profile_plist}"
)" || fail "the embedded profile has no App Group entitlement"
[[ "${profile_app_groups}" == *"BUUH229D5Q.*"* ]] \
    || fail "the embedded profile does not authorize the team App Group"

package_size="$(/usr/bin/stat -f '%z' "${package_path}")"
[[ "${package_size}" == <1-> ]] \
    || fail "the installer package size is invalid"
package_sha256="$(/usr/bin/shasum -a 256 "${package_path}" | /usr/bin/awk '{print $1}')"

print "QuotaView App Store export checks passed."
print "Package: ${package_path:t}"
print "Size: ${package_size} bytes"
print "SHA-256: ${package_sha256}"
print \
    "Payload: signatures, sandbox entitlements, executables, and dependencies verified"
print "Profile: ${profile_name} / ${profile_uuid} / expires ${profile_expiration}"
