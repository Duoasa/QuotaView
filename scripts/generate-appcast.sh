#!/bin/zsh

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    print -u2 \
        "Usage: $0 <archives-directory> <release-tag>"
    print -u2 \
        "Example: $0 /tmp/quotaview-updates v0.3.5-build.4"
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
expected_tag="v${version}-build.${build_number}"
release_name="QuotaView-v${version}-build.${build_number}"
release_archive="${archives_dir}/${release_name}.zip"
appcast_path="${archives_dir}/appcast.xml"
sparkle_key_account="${SPARKLE_KEY_ACCOUNT:-com.quotaview.menubar}"

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

"${generate_appcast_tool}" \
    --account "${sparkle_key_account}" \
    --download-url-prefix "${download_url_prefix}" \
    --full-release-notes-url "${release_url}" \
    --link "https://github.com/Duoasa/QuotaView" \
    --maximum-versions 3 \
    --maximum-deltas 0 \
    -o "${appcast_path}" \
    "${archives_dir}"

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
