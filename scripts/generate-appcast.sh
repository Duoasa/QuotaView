#!/bin/zsh

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    print -u2 \
        "Usage: $0 <archives-directory> <release-tag>"
    print -u2 \
        "Example: $0 /tmp/quotaview-updates v0.3.6-build.2"
    exit 2
fi

archives_dir="${1:A}"
release_tag="$2"
script_dir="${0:A:h}"
project_dir="${script_dir:h}"
info_plist="${project_dir}/Support/Info.plist"
version="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "${info_plist}"
)"
build_number="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleVersion' \
        "${info_plist}"
)"
display_build_number="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :QuotaViewDisplayBuildNumber' \
        "${info_plist}"
)"
expected_tag="v${version}-build.${display_build_number}"
release_name="QuotaView-v${version}-build.${display_build_number}"
release_archive="${archives_dir}/${release_name}.zip"
appcast_path="${archives_dir}/appcast.xml"
sparkle_key_account="${SPARKLE_KEY_ACCOUNT:-com.quotaview.menubar}"
expected_feed_url="$(
    /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "${info_plist}"
)"
expected_public_key="$(
    /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${info_plist}"
)"
expected_signing_team="$(
    /usr/libexec/PlistBuddy -c 'Print :QuotaViewUpdateTeamIdentifier' "${info_plist}"
)"

if [[ "${release_tag}" != "${expected_tag}" ]]; then
    print -u2 \
        "Release tag mismatch: expected ${expected_tag}, " \
        "received ${release_tag}."
    exit 2
fi

if [[ ! -d "${archives_dir}" ]]; then
    print -u2 "Archives directory does not exist: ${archives_dir}"
    exit 2
fi

if [[ ! -f "${release_archive}" ]]; then
    print -u2 "Missing release archive: ${release_archive}"
    exit 2
fi

# Check the actual archive before accessing the signing key. A development
# bundle with the right version number must never become a stable update.
verification_dir="$(mktemp -d "/tmp/quotaview-appcast-check.XXXXXX")"
trap 'rm -rf "${verification_dir}"' EXIT
/usr/bin/ditto -x -k "${release_archive}" "${verification_dir}"
archive_app="${verification_dir}/QuotaView.app"
archive_info="${archive_app}/Contents/Info.plist"
widget_info="${archive_app}/Contents/PlugIns/QuotaViewWidgetExtension.appex/Contents/Info.plist"
if [[ ! -f "${archive_info}" ]] || [[ ! -f "${widget_info}" ]]; then
    print -u2 "Stable archive must contain QuotaView.app and its widget."
    exit 4
fi

for plist in "${archive_info}" "${widget_info}"; do
    if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${plist}")" != "${version}" ]] \
        || [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${plist}")" != "${build_number}" ]] \
        || [[ "$(/usr/libexec/PlistBuddy -c 'Print :QuotaViewDisplayBuildNumber' "${plist}")" != "${display_build_number}" ]] \
        || [[ "$(/usr/libexec/PlistBuddy -c 'Print :QuotaViewAppGroupIdentifier' "${plist}")" != "BUUH229D5Q.com.quotaview.shared" ]]; then
        print -u2 "Stable archive version or App Group identity is inconsistent."
        exit 4
    fi
done
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${archive_info}")" != "com.quotaview.menubar" ]] \
    || [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${widget_info}")" != "com.quotaview.menubar.widget" ]] \
    || [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "${archive_info}")" != "${expected_feed_url}" ]] \
    || [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${archive_info}")" != "${expected_public_key}" ]] \
    || [[ "$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "${archive_info}")" != "true" ]] \
    || [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "${archive_info}")" != "true" ]]; then
    print -u2 "Stable archive application or Sparkle identity is inconsistent."
    exit 4
fi
codesign --verify --deep --strict "${archive_app}"
signature_details="$(codesign -dv --verbose=4 "${archive_app}" 2>&1)"
if ! print -r -- "${signature_details}" | rg -Fq "TeamIdentifier=${expected_signing_team}" \
    || ! print -r -- "${signature_details}" | rg -Fq 'Authority=Developer ID Application:'; then
    print -u2 "Stable appcast requires the official Developer ID signature."
    exit 4
fi
xcrun stapler validate "${archive_app}"

if find "${archives_dir}" \
    -maxdepth 1 \
    -type f \
    -iname '*preview*.zip' \
    -print \
    -quit \
    | grep -q .; then
    print -u2 "Stable appcast input must not contain preview archives."
    exit 2
fi

generate_appcast_tool="${SPARKLE_GENERATE_APPCAST:-}"
sign_update_tool="${SPARKLE_SIGN_UPDATE:-}"
sparkle_artifacts_dir="${project_dir}/.build/artifacts"

if [[ -z "${generate_appcast_tool}" ]] \
    && [[ -d "${sparkle_artifacts_dir}" ]]; then
    generate_appcast_tool="$(
        find "${sparkle_artifacts_dir}" \
            -path '*/Sparkle/bin/generate_appcast' \
            -type f \
            -perm -111 \
            -print \
            -quit
    )"
fi
if [[ -z "${sign_update_tool}" ]] \
    && [[ -d "${sparkle_artifacts_dir}" ]]; then
    sign_update_tool="$(
        find "${sparkle_artifacts_dir}" \
            -path '*/Sparkle/bin/sign_update' \
            -type f \
            -perm -111 \
            -print \
            -quit
    )"
fi

if [[ ! -x "${generate_appcast_tool}" ]] \
    || [[ ! -x "${sign_update_tool}" ]]; then
    print -u2 \
        "Sparkle publishing tools are unavailable. Run " \
        "'swift package resolve' first."
    exit 3
fi

download_url_prefix="https://github.com/Duoasa/QuotaView/releases/download/${release_tag}/"
release_url="https://github.com/Duoasa/QuotaView/releases/tag/${release_tag}"

# Generate from only the selected immutable archive. The existing output feed
# still supplies historical items, whose version-specific GitHub URLs must not
# be rewritten using this release's download prefix.
generation_dir="${verification_dir}/archives"
mkdir -p "${generation_dir}"
/usr/bin/ditto "${release_archive}" "${generation_dir}/${release_name}.zip"

"${generate_appcast_tool}" \
    --account "${sparkle_key_account}" \
    --download-url-prefix "${download_url_prefix}" \
    --full-release-notes-url "${release_url}" \
    --link "https://github.com/Duoasa/QuotaView" \
    --maximum-versions 3 \
    --maximum-deltas 0 \
    -o "${appcast_path}" \
    "${generation_dir}"

"${sign_update_tool}" \
    --account "${sparkle_key_account}" \
    --verify \
    "${appcast_path}"

if ! rg -Fq \
    "<sparkle:version>${build_number}</sparkle:version>" \
    "${appcast_path}" \
    || ! rg -Fq \
        "<sparkle:shortVersionString>${version}</sparkle:shortVersionString>" \
        "${appcast_path}" \
    || ! rg -Fq \
        '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>' \
        "${appcast_path}" \
    || ! rg -Fq \
        "${download_url_prefix}${release_name}.zip" \
        "${appcast_path}" \
    || ! rg -Fq 'sparkle:edSignature=' "${appcast_path}" \
    || ! rg -Fq 'sparkle-signatures:' "${appcast_path}"; then
    print -u2 "Generated appcast does not match the release identity."
    exit 4
fi

print "Generated and verified ${appcast_path}"
print "Publish it only after the immutable GitHub Release asset is live."
