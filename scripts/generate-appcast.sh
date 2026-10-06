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
sealed_manifest="${archives_dir}/${release_name}.manifest.json"
sparkle_key_account="${SPARKLE_KEY_ACCOUNT:-com.quotaview.menubar}"
# A new sealed directory has no previous feed; require its explicit source.
base_appcast="${SPARKLE_APPCAST_BASE_FEED:-${appcast_path}}"
initial_feed="${SPARKLE_APPCAST_INITIAL_FEED:-NO}"
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

if [[ ! -f "${sealed_manifest}" ]]; then
    print -u2 "Missing sealed manifest: ${sealed_manifest}"
    exit 4
fi

if [[ ! -f "${base_appcast}" ]] && [[ "${initial_feed}" != "YES" ]]; then
    print -u2 "Missing previous verified appcast. Set SPARKLE_APPCAST_BASE_FEED to its exact path."
    print -u2 "SPARKLE_APPCAST_INITIAL_FEED=YES is only for an explicitly intended first feed."
    exit 4
fi

# Check the actual archive before accessing the signing key. A development
# bundle with the right version number must never become a stable update.
verification_dir="$(mktemp -d "/tmp/quotaview-appcast-check.XXXXXX")"
trap 'rm -rf "${verification_dir}"' EXIT
# AUDIT-027: BEGIN APPCAST BINDING
# Verify sealed bytes and the canonical public download before touching a key
# or emitting a feed. A locally re-created ZIP is not public-download evidence.
download_url_prefix="https://github.com/Duoasa/QuotaView/releases/download/${release_tag}/"
release_url="https://github.com/Duoasa/QuotaView/releases/tag/${release_tag}"
public_archive="${verification_dir}/${release_name}.download.zip"
python3 - "${sealed_manifest}" "${release_archive}" "${release_name}" <<'PY'
import hashlib, json, re, sys
from pathlib import Path
manifest_path, archive_path, name = sys.argv[1:]
manifest = json.loads(Path(manifest_path).read_text())
archive = Path(archive_path)
def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()
def require(condition, message):
    if not condition: raise SystemExit(message)
require(manifest['format'] == 1 and manifest['releaseName'] == name, 'Sealed identity mismatch')
require(re.fullmatch(r'[0-9a-f]{40}', manifest['sourceCommit']), 'Missing source commit')
require(manifest['sourceDirty'] is False, 'Stable feed requires a clean source commit')
require(manifest['signing']['developerID'] is True and manifest['signing']['notarized'] is True, 'Missing Developer ID/notarization evidence')
sealed = manifest['archive']
require(sealed['name'] == archive.name == name + '.zip', 'Sealed archive name mismatch')
require(sealed['length'] == archive.stat().st_size and sealed['sha256'] == digest(archive), 'Sealed archive bytes mismatch')
require(isinstance(sealed['sparkleSignature'], str) and bool(sealed['sparkleSignature']), 'Missing sealed Sparkle archive signature')
PY
curl --fail --location --proto '=https' --tlsv1.2 \
    --connect-timeout 15 --max-time 300 \
    --output "${public_archive}" "${download_url_prefix}${release_name}.zip"
python3 - "${sealed_manifest}" "${public_archive}" <<'PY'
import hashlib, json, sys
from pathlib import Path
manifest = json.loads(Path(sys.argv[1]).read_text())['archive']
download = Path(sys.argv[2])
value = hashlib.sha256()
with download.open('rb') as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        value.update(chunk)
if value.hexdigest() != manifest['sha256']:
    raise SystemExit('Public archive SHA-256 differs from sealed bytes')
if download.stat().st_size != manifest['length']:
    raise SystemExit('Public archive length differs from sealed bytes')
PY
# AUDIT-027: END APPCAST BINDING
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

# Generate from only the selected immutable archive. The existing output feed
# still supplies historical items, whose version-specific GitHub URLs must not
# be rewritten using this release's download prefix.
generation_dir="${verification_dir}/archives"
mkdir -p "${generation_dir}"
staged_appcast="${verification_dir}/appcast.xml"
if [[ -f "${base_appcast}" ]]; then
    /usr/bin/ditto "${base_appcast}" "${staged_appcast}"
    "${sign_update_tool}" --account "${sparkle_key_account}" --verify "${staged_appcast}"
    python3 - "${staged_appcast}" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
if root.tag != "rss" or root.find("channel") is None:
    raise SystemExit("Previous appcast must be an RSS channel")
PY
fi
sealed_signature="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["archive"]["sparkleSignature"])' "${sealed_manifest}")"
"${sign_update_tool}" --account "${sparkle_key_account}" --verify "${release_archive}" "${sealed_signature}"
/usr/bin/ditto "${release_archive}" "${generation_dir}/${release_name}.zip"

"${generate_appcast_tool}" \
    --account "${sparkle_key_account}" \
    --download-url-prefix "${download_url_prefix}" \
    --full-release-notes-url "${release_url}" \
    --link "https://github.com/Duoasa/QuotaView" \
    --maximum-versions 3 \
    --maximum-deltas 0 \
    -o "${staged_appcast}" \
    "${generation_dir}"

"${sign_update_tool}" \
    --account "${sparkle_key_account}" \
    --verify \
    "${staged_appcast}"

if ! rg -Fq \
    "<sparkle:version>${build_number}</sparkle:version>" \
    "${staged_appcast}" \
    || ! rg -Fq \
        "<sparkle:shortVersionString>${version}</sparkle:shortVersionString>" \
        "${staged_appcast}" \
    || ! rg -Fq \
        '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>' \
        "${staged_appcast}" \
    || ! rg -Fq \
        "${download_url_prefix}${release_name}.zip" \
        "${staged_appcast}" \
    || ! rg -Fq 'sparkle:edSignature=' "${staged_appcast}" \
    || ! rg -Fq 'sparkle-signatures:' "${staged_appcast}"; then
    print -u2 "Generated appcast does not match the release identity."
    exit 4
fi

python3 - "${sealed_manifest}" "${staged_appcast}" "${download_url_prefix}${release_name}.zip" "${build_number}" <<'PY'
import json, sys, xml.etree.ElementTree as ET
from pathlib import Path
sealed = json.loads(Path(sys.argv[1]).read_text())['archive']
root = ET.parse(sys.argv[2]).getroot()
namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = [item for item in root.findall('./channel/item')
         if item.findtext(namespace + 'version') == sys.argv[4]]
def require(condition, message):
    if not condition: raise SystemExit(message)
require(len(items) == 1, 'Expected exactly one item for the selected build')
enclosure = items[0].find('enclosure')
require(enclosure is not None and enclosure.get('url') == sys.argv[3], 'Feed enclosure URL mismatch')
require(int(enclosure.get('length', '-1')) == sealed['length'], 'Feed enclosure length mismatch')
require(enclosure.get(namespace + 'edSignature') == sealed['sparkleSignature'], 'Feed archive signature mismatch')
PY
# Only a fully verified staged feed can replace the previous local output.
python3 - "${staged_appcast}" "${appcast_path}" <<'PY'
import os, shutil, sys, tempfile
from pathlib import Path
destination = Path(sys.argv[2])
candidate = None
try:
    with tempfile.NamedTemporaryFile(prefix='.appcast.', dir=destination.parent, delete=False) as stream:
        candidate = Path(stream.name)
    shutil.copyfile(sys.argv[1], candidate)
    candidate.chmod(0o644)
    os.replace(candidate, destination)
    candidate = None
finally:
    if candidate is not None:
        candidate.unlink()
PY
print "Generated and verified ${appcast_path}"
print "Canonical public archive SHA-256 and length match the sealed manifest."
