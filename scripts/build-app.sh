#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
project_file="${project_dir}/QuotaView.xcodeproj"
distribution_config="${project_dir}/Configs/Distribution.xcconfig"
scheme="QuotaView"
configuration="Release"
dist_dir="${project_dir}/dist"
info_plist="${project_dir}/Support/Info.plist"
app_entitlements="${project_dir}/Support/QuotaView.entitlements"
widget_entitlements="${project_dir}/Support/QuotaViewWidget.entitlements"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}")"
display_build_number="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :QuotaViewDisplayBuildNumber' \
        "${info_plist}"
)"
# Release packaging explicitly uses the stable identity; source/default builds
# keep the independent development data, activity socket and update boundary.
app_group_identifier="BUUH229D5Q.com.quotaview.shared"
update_team_identifier="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :QuotaViewUpdateTeamIdentifier' \
        "${info_plist}"
)"
sparkle_feed_url="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :SUFeedURL' \
        "${info_plist}"
)"
sparkle_public_key="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :SUPublicEDKey' \
        "${info_plist}"
)"
release_name="QuotaView-v${version}-build.${display_build_number}"
release_channel="$(
    /usr/libexec/PlistBuddy -c 'Print :QuotaViewReleaseChannel' "${info_plist}" 2>/dev/null || true
)"
if [[ "${release_channel}" == "preview" ]]; then
    preview_number="$(
        /usr/libexec/PlistBuddy -c 'Print :QuotaViewPreviewNumber' "${info_plist}"
    )"
    if [[ "${preview_number}" != <1-> ]]; then
        print -u2 "Expected a positive QuotaViewPreviewNumber."
        exit 2
    fi
    release_name="QuotaView-v${version}-preview.${preview_number}"
fi
staging_dir="$(mktemp -d "/tmp/quotaview-package.XXXXXX")"
verification_dir="$(mktemp -d "/tmp/quotaview-verify.XXXXXX")"
derived_data="${staging_dir}/DerivedData"
built_app="${derived_data}/Build/Products/${configuration}/QuotaView.app"
staging_app="${staging_dir}/QuotaView.app"
widget_extension="${staging_app}/Contents/PlugIns/QuotaViewWidgetExtension.appex"
activity_helper="${staging_app}/Contents/Helpers/QuotaViewActivityHook"
sparkle_framework="${staging_app}/Contents/Frameworks/Sparkle.framework"
sparkle_version_dir="${sparkle_framework}/Versions/B"
sparkle_installer_xpc="${sparkle_version_dir}/XPCServices/Installer.xpc"
sparkle_downloader_xpc="${sparkle_version_dir}/XPCServices/Downloader.xpc"
sparkle_autoupdate="${sparkle_version_dir}/Autoupdate"
sparkle_updater_app="${sparkle_version_dir}/Updater.app"
destination_release="${dist_dir}/${release_name}"
destination_app="${destination_release}/QuotaView.app"
staging_zip="${staging_dir}/${release_name}.zip"
destination_zip="${destination_release}/${release_name}.zip"
destination_manifest="${destination_release}/${release_name}.manifest.json"
signing_identity="${CODESIGN_IDENTITY:-}"
notary_profile="${NOTARY_PROFILE:-}"
sparkle_key_account="${SPARKLE_KEY_ACCOUNT:-com.quotaview.menubar}"
identity_inventory="$(security find-identity -v -p codesigning)"

if [[ -z "${signing_identity}" ]]; then
    signing_identity="$(
        print -r -- "${identity_inventory}" \
            | sed -n \
                's/^[[:space:]]*[0-9][0-9]*) \([[:xdigit:]]\{40\}\) "Developer ID Application:[^"]*".*$/\1/p' \
            | tail -n 1
    )"

    if [[ -z "${signing_identity}" ]]; then
        signing_identity="$(
            print -r -- "${identity_inventory}" \
                | sed -n \
                    's/^[[:space:]]*[0-9][0-9]*) \([[:xdigit:]]\{40\}\) "Apple Development:[^"]*".*$/\1/p' \
                | head -n 1
        )"
    fi

    if [[ -z "${signing_identity}" ]]; then
        signing_identity="-"
    fi
fi

signing_common_name="${signing_identity}"
if [[ "${signing_identity}" != "-" ]]; then
    if ! print -r -- "${signing_identity}" \
        | grep -Eq '^[[:xdigit:]]{40}$'; then
        matching_identity_hashes="$(
            print -r -- "${identity_inventory}" \
                | awk -v requested="\"${signing_identity}\"" \
                    'index($0, requested) { print $2 }'
        )"
        matching_identity_count="$(
            print -r -- "${matching_identity_hashes}" \
                | awk 'NF { count += 1 } END { print count + 0 }'
        )"
        if [[ "${matching_identity_count}" -ne 1 ]]; then
            print -u2 \
                "Signing identity name is missing or ambiguous: " \
                "${signing_identity}"
            print -u2 \
                "Set CODESIGN_IDENTITY to one exact 40-character " \
                "certificate SHA-1 fingerprint."
            exit 2
        fi
        signing_identity="${matching_identity_hashes}"
    fi

    signing_common_name="$(
        print -r -- "${identity_inventory}" \
            | awk -v requested="${signing_identity}" '
                $2 == requested {
                    if (match($0, /"[^"]+"/)) {
                        print substr($0, RSTART + 1, RLENGTH - 2)
                    }
                }
            '
    )"
fi

is_developer_id=false
if [[ "${signing_common_name}" == "Developer ID Application:"* ]]; then
    is_developer_id=true
fi

cleanup() {
    rm -rf "${staging_dir}"
    rm -rf "${verification_dir}"
}
trap cleanup EXIT

if [[ "${signing_identity}" != "-" ]]; then
    if [[ "${identity_inventory}" != *"${signing_identity}"* ]] \
        || [[ -z "${signing_common_name}" ]]; then
        print -u2 "Signing identity not found: ${signing_identity}"
        print -u2 "Install or repair the requested code signing identity first."
        exit 2
    fi
fi

if [[ -n "${notary_profile}" ]] && [[ "${is_developer_id}" != true ]]; then
    print -u2 "NOTARY_PROFILE requires a Developer ID Application signature."
    exit 2
fi

if [[ "${is_developer_id}" == true ]] \
    && [[ "${SPARKLE_KEY_BACKUP_CONFIRMED:-NO}" != "YES" ]]; then
    print -u2 \
        "Developer ID packaging requires an encrypted offline backup " \
        "of the Sparkle EdDSA private key."
    print -u2 \
        "After verifying the backup, rerun with " \
        "SPARKLE_KEY_BACKUP_CONFIRMED=YES."
    exit 2
fi

mkdir -p "${dist_dir}"

cd "${project_dir}"

# Freeze provenance before the compiler reads source inputs.
source_identity_file="${staging_dir}/source-identity.json"
python3 "${script_dir}/release-source-identity.py" capture "${project_dir}" "${source_identity_file}"

xcodebuild \
    -project "${project_file}" \
    -scheme "${scheme}" \
    -configuration "${configuration}" \
    -xcconfig "${distribution_config}" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "${derived_data}" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    clean build

python3 "${script_dir}/release-source-identity.py" verify "${project_dir}" "${source_identity_file}"

if [[ ! -d "${built_app}" ]]; then
    print -u2 "Xcode did not produce ${built_app}"
    exit 3
fi

/usr/bin/ditto "${built_app}" "${staging_app}"
xattr -cr "${staging_app}"

if [[ ! -d "${widget_extension}" ]]; then
    print -u2 "Missing embedded widget extension: ${widget_extension}"
    exit 3
fi

if [[ ! -x "${activity_helper}" ]]; then
    print -u2 "Missing embedded Codex activity helper: ${activity_helper}"
    exit 3
fi

for sparkle_component in \
    "${sparkle_framework}" \
    "${sparkle_installer_xpc}" \
    "${sparkle_downloader_xpc}" \
    "${sparkle_autoupdate}" \
    "${sparkle_updater_app}"; do
    if [[ ! -e "${sparkle_component}" ]]; then
        print -u2 "Missing embedded Sparkle component: ${sparkle_component}"
        exit 3
    fi
done

signing_args=(
    --force
    --sign "${signing_identity}"
)

if [[ "${signing_identity}" == "-" ]]; then
    signing_args+=(--timestamp=none)
else
    signing_args+=(--options runtime --timestamp)
fi

codesign "${signing_args[@]}" "${sparkle_installer_xpc}"
codesign \
    "${signing_args[@]}" \
    --preserve-metadata=entitlements \
    "${sparkle_downloader_xpc}"
codesign "${signing_args[@]}" "${sparkle_autoupdate}"
codesign "${signing_args[@]}" "${sparkle_updater_app}"
codesign "${signing_args[@]}" "${sparkle_framework}"

for framework in "${staging_app}"/Contents/Frameworks/*.framework(N); do
    if [[ "${framework}" == "${sparkle_framework}" ]]; then
        continue
    fi
    codesign "${signing_args[@]}" "${framework}"
done

for library in "${staging_app}"/Contents/Frameworks/*.dylib(N); do
    codesign "${signing_args[@]}" "${library}"
done

for framework in "${widget_extension}"/Contents/Frameworks/*.framework(N); do
    codesign "${signing_args[@]}" "${framework}"
done

for library in "${widget_extension}"/Contents/Frameworks/*.dylib(N); do
    codesign "${signing_args[@]}" "${library}"
done

codesign "${signing_args[@]}" "${activity_helper}"

codesign \
    "${signing_args[@]}" \
    --entitlements "${widget_entitlements}" \
    "${widget_extension}"
codesign \
    "${signing_args[@]}" \
    --entitlements "${app_entitlements}" \
    "${staging_app}"
codesign --verify --deep --strict --verbose=4 "${staging_app}"

signature_details="$(codesign -dv --verbose=4 "${staging_app}" 2>&1)"
widget_signature_details="$(
    codesign -dv --verbose=4 "${widget_extension}" 2>&1
)"
helper_signature_details="$(
    codesign -dv --verbose=4 "${activity_helper}" 2>&1
)"
if [[ "${signing_identity}" == "-" ]]; then
    if print -r -- "${signature_details}" | grep -q 'flags=.*runtime' \
        || print -r -- "${widget_signature_details}" \
            | grep -q 'flags=.*runtime' \
        || print -r -- "${helper_signature_details}" \
            | grep -q 'flags=.*runtime'; then
        print -u2 \
            "Ad-hoc builds must not enable Hardened Runtime; " \
            "embedded code would fail Library Validation at launch."
        exit 4
    fi
else
    if ! print -r -- "${signature_details}" \
        | grep -q 'flags=.*runtime' \
        || ! print -r -- "${widget_signature_details}" \
            | grep -q 'flags=.*runtime' \
        || ! print -r -- "${helper_signature_details}" \
            | grep -q 'flags=.*runtime'; then
        print -u2 \
            "Signed app, widget, or activity helper is missing the Hardened Runtime flag."
        exit 4
    fi
fi

built_version="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "${staging_app}/Contents/Info.plist"
)"
built_bundle_identifier="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleIdentifier' \
        "${staging_app}/Contents/Info.plist"
)"
built_app_group_identifier="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :QuotaViewAppGroupIdentifier' \
        "${staging_app}/Contents/Info.plist"
)"
widget_app_group_identifier="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :QuotaViewAppGroupIdentifier' \
        "${widget_extension}/Contents/Info.plist"
)"
built_build_number="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleVersion' \
        "${staging_app}/Contents/Info.plist"
)"
built_display_build_number="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :QuotaViewDisplayBuildNumber' \
        "${staging_app}/Contents/Info.plist"
)"
widget_version="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "${widget_extension}/Contents/Info.plist"
)"
widget_build_number="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleVersion' \
        "${widget_extension}/Contents/Info.plist"
)"
widget_display_build_number="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :QuotaViewDisplayBuildNumber' \
        "${widget_extension}/Contents/Info.plist"
)"
widget_bundle_identifier="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleIdentifier' \
        "${widget_extension}/Contents/Info.plist"
)"
widget_extension_point="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :NSExtension:NSExtensionPointIdentifier' \
        "${widget_extension}/Contents/Info.plist"
)"
built_update_team_identifier="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :QuotaViewUpdateTeamIdentifier' \
        "${staging_app}/Contents/Info.plist"
)"
built_sparkle_feed_url="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :SUFeedURL' \
        "${staging_app}/Contents/Info.plist"
)"
built_sparkle_public_key="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :SUPublicEDKey' \
        "${staging_app}/Contents/Info.plist"
)"
built_sparkle_automatic_checks="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :SUEnableAutomaticChecks' \
        "${staging_app}/Contents/Info.plist"
)"
built_sparkle_allows_automatic_updates="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :SUAllowsAutomaticUpdates' \
        "${staging_app}/Contents/Info.plist"
)"
built_sparkle_verify_before_extraction="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :SUVerifyUpdateBeforeExtraction' \
        "${staging_app}/Contents/Info.plist"
)"
built_sparkle_requires_signed_feed="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :SURequireSignedFeed' \
        "${staging_app}/Contents/Info.plist"
)"

if [[ "${built_version}" != "${version}" ]] \
    || [[ "${built_build_number}" != "${build_number}" ]] \
    || [[ "${built_display_build_number}" \
        != "${display_build_number}" ]]; then
    print -u2 \
        "Version mismatch: expected ${version} Build " \
        "${display_build_number} (update ${build_number}), built " \
        "${built_version} Build ${built_display_build_number} " \
        "(update ${built_build_number})"
    exit 4
fi

if [[ "${widget_version}" != "${version}" ]] \
    || [[ "${widget_build_number}" != "${build_number}" ]] \
    || [[ "${widget_display_build_number}" \
        != "${display_build_number}" ]]; then
    print -u2 \
        "Widget version mismatch: expected ${version} Build " \
        "${display_build_number} (update ${build_number}), built " \
        "${widget_version} Build ${widget_display_build_number} " \
        "(update ${widget_build_number})"
    exit 4
fi

if [[ "${built_bundle_identifier}" != "com.quotaview.menubar" ]] \
    || [[ "${built_app_group_identifier}" != "${app_group_identifier}" ]] \
    || [[ "${widget_app_group_identifier}" != "${app_group_identifier}" ]]; then
    print -u2 "Release packaging must use the stable app and App Group identity."
    exit 4
fi

if [[ "${widget_bundle_identifier}" \
        != "com.quotaview.menubar.widget" ]]; then
    print -u2 \
        "Unexpected widget bundle identifier: ${widget_bundle_identifier}"
    exit 4
fi

if [[ "${widget_extension_point}" \
        != "com.apple.widgetkit-extension" ]]; then
    print -u2 \
        "Unexpected widget extension point: ${widget_extension_point}"
    exit 4
fi

if [[ "${built_update_team_identifier}" \
        != "${update_team_identifier}" ]] \
    || [[ "${built_sparkle_feed_url}" != "${sparkle_feed_url}" ]] \
    || [[ "${built_sparkle_public_key}" != "${sparkle_public_key}" ]] \
    || [[ "${built_sparkle_automatic_checks}" != "false" ]] \
    || [[ "${built_sparkle_allows_automatic_updates}" != "false" ]] \
    || [[ "${built_sparkle_verify_before_extraction}" != "true" ]] \
    || [[ "${built_sparkle_requires_signed_feed}" != "true" ]]; then
    print -u2 "Sparkle update configuration is missing or inconsistent."
    exit 4
fi

for resource in AppIcon.icns Assets.car; do
    if [[ ! -f "${staging_app}/Contents/Resources/${resource}" ]]; then
        print -u2 "Missing packaged resource: ${resource}"
        exit 4
    fi
done

architectures="$(
    lipo -archs "${staging_app}/Contents/MacOS/QuotaView"
)"
widget_architectures="$(
    lipo -archs \
        "${widget_extension}/Contents/MacOS/QuotaViewWidgetExtension"
)"
helper_architectures="$(
    lipo -archs "${activity_helper}"
)"

if [[ " ${architectures} " != *" arm64 "* ]] \
    || [[ " ${architectures} " != *" x86_64 "* ]]; then
    print -u2 "Expected a universal binary, found: ${architectures}"
    exit 4
fi

if [[ " ${widget_architectures} " != *" arm64 "* ]] \
    || [[ " ${widget_architectures} " != *" x86_64 "* ]]; then
    print -u2 \
        "Expected a universal widget binary, found: " \
        "${widget_architectures}"
    exit 4
fi

if [[ " ${helper_architectures} " != *" arm64 "* ]] \
    || [[ " ${helper_architectures} " != *" x86_64 "* ]]; then
    print -u2 \
        "Expected a universal activity helper, found: " \
        "${helper_architectures}"
    exit 4
fi

for framework in "${staging_app}"/Contents/Frameworks/*.framework(N); do
    framework_name="${framework:t:r}"
    framework_binary="${framework}/Versions/Current/${framework_name}"
    if [[ ! -f "${framework_binary}" ]]; then
        print -u2 "Missing framework executable: ${framework_binary}"
        exit 4
    fi

    framework_architectures="$(lipo -archs "${framework_binary}")"
    if [[ " ${framework_architectures} " != *" arm64 "* ]] \
        || [[ " ${framework_architectures} " != *" x86_64 "* ]]; then
        print -u2 \
            "Expected universal ${framework_name}, " \
            "found: ${framework_architectures}"
        exit 4
    fi
done

sparkle_binaries=(
    "${sparkle_version_dir}/Sparkle"
    "${sparkle_installer_xpc}/Contents/MacOS/Installer"
    "${sparkle_downloader_xpc}/Contents/MacOS/Downloader"
    "${sparkle_autoupdate}"
    "${sparkle_updater_app}/Contents/MacOS/Updater"
)
for sparkle_binary in "${sparkle_binaries[@]}"; do
    if [[ ! -f "${sparkle_binary}" ]]; then
        print -u2 "Missing Sparkle executable: ${sparkle_binary}"
        exit 4
    fi

    sparkle_architectures="$(lipo -archs "${sparkle_binary}")"
    if [[ " ${sparkle_architectures} " != *" arm64 "* ]] \
        || [[ " ${sparkle_architectures} " != *" x86_64 "* ]]; then
        print -u2 \
            "Expected a universal Sparkle executable, found: " \
            "${sparkle_architectures}"
        exit 4
    fi
done

app_entitlement_details="$(
    codesign -d --entitlements - "${staging_app}" 2>&1
)"
widget_entitlement_details="$(
    codesign -d --entitlements - "${widget_extension}" 2>&1
)"
if [[ "${app_entitlement_details}" \
        != *"${app_group_identifier}"* ]] \
    || [[ "${widget_entitlement_details}" \
        != *"${app_group_identifier}"* ]] \
    || [[ "${widget_entitlement_details}" \
        != *"com.apple.security.app-sandbox"* ]]; then
    print -u2 \
        "App Group or widget sandbox entitlements are missing."
    exit 4
fi

if [[ "${app_group_identifier}" != "BUUH229D5Q."* ]] \
    && [[ ! -f "${staging_app}/Contents/embedded.provisionprofile" ]]; then
    print -u2 \
        "Notarized direct distribution requires a team-prefixed App Group " \
        "or an embedded provisioning profile."
    exit 4
fi

if [[ -n "${notary_profile}" ]]; then
    notary_zip="${staging_dir}/${release_name}-notary.zip"
    /usr/bin/ditto \
        -c \
        -k \
        --keepParent \
        "${staging_app}" \
        "${notary_zip}"
    xcrun notarytool submit \
        "${notary_zip}" \
        --keychain-profile "${notary_profile}" \
        --wait
    xcrun stapler staple "${staging_app}"
    xcrun stapler validate "${staging_app}"
    spctl --assess --type execute --verbose=4 "${staging_app}"
fi

/usr/bin/ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "${staging_app}" \
    "${staging_zip}"

/usr/bin/ditto -x -k "${staging_zip}" "${verification_dir}"
codesign \
    --verify \
    --deep \
    --strict \
    --verbose=4 \
    "${verification_dir}/QuotaView.app"
staging_zip_sha256="$(
    shasum -a 256 "${staging_zip}" | awk '{print $1}'
)"

# AUDIT-027: BEGIN SEAL
# Validate the candidate before touching any sealed output or historical App.
sparkle_signature=""
sparkle_archive_length="$(stat -f '%z' "${staging_zip}")"
if [[ "${is_developer_id}" == true ]]; then
    sign_update_tool="$(
        find "${derived_data}/SourcePackages/artifacts" \
            -path '*/Sparkle/bin/sign_update' -type f -perm -111 -print -quit
    )"
    if [[ -z "${sign_update_tool}" ]]; then
        print -u2 "Sparkle sign_update tool was not resolved."
        exit 4
    fi
    sparkle_signature="$(
        "${sign_update_tool}" --account "${sparkle_key_account}" -p "${staging_zip}"
    )"
    if [[ -z "${sparkle_signature}" ]]; then
        print -u2 "Sparkle returned an empty archive signature."
        exit 4
    fi
    "${sign_update_tool}" --account "${sparkle_key_account}" --verify \
        "${staging_zip}" "${sparkle_signature}"
fi

python3 "${script_dir}/release-source-identity.py" verify "${project_dir}" "${source_identity_file}"
source_commit="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "${source_identity_file}")"
source_dirty="$(python3 -c 'import json,sys; print("dirty" if json.load(open(sys.argv[1]))["dirty"] else "")' "${source_identity_file}")"
python3 - "${staging_app}" "${staging_zip}" "${destination_release}" \
    "${release_name}" "${staging_zip_sha256}" "${source_commit}" \
    "${source_dirty}" "${signing_identity}" "${is_developer_id}" \
    "${notary_profile}" "${sparkle_signature}" <<'PY'
import hashlib, json, os, plistlib, shutil, sys, tempfile
from pathlib import Path

(app_arg, zip_arg, release_arg, name, expected_sha, commit, dirty,
 signer, developer_id, notary_profile, signature) = sys.argv[1:]
app, archive, release = map(Path, (app_arg, zip_arg, release_arg))
dist = release.parent
lock = dist / ('.' + name + '.seal-lock')
candidate = None
locked = False

def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()

def app_tree(path):
    entries = []
    for file in sorted(path.rglob('*')):
        relative = file.relative_to(path).as_posix()
        if file.is_symlink():
            entries.append([relative, 'symlink', os.readlink(file)])
        elif file.is_file():
            entries.append([relative, file.stat().st_mode & 0o777, digest(file)])
        elif file.is_dir():
            entries.append([relative, 'directory'])
    return hashlib.sha256(json.dumps(entries, separators=(',', ':')).encode()).hexdigest()

def identity(path):
    data = plistlib.loads(path.read_bytes())
    keys = ['CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion',
            'QuotaViewDisplayBuildNumber', 'QuotaViewAppGroupIdentifier']
    return {key: data[key] for key in keys}

try:
    if digest(archive) != expected_sha:
        raise ValueError('Staging archive changed after verification')
    manifest = {
        'format': 1,
        'releaseName': name,
        'sourceCommit': commit,
        'sourceDirty': bool(dirty),
        'archive': {'name': archive.name, 'sha256': expected_sha,
                    'length': archive.stat().st_size, 'sparkleSignature': signature},
        'appTreeSHA256': app_tree(app),
        'identity': {
            'app': identity(app / 'Contents/Info.plist'),
            'widget': identity(app / 'Contents/PlugIns/QuotaViewWidgetExtension.appex/Contents/Info.plist')
        },
        'signing': {'identity': signer, 'developerID': developer_id == 'true',
                    'notarized': bool(notary_profile)}
    }
    # Old flat-layout artifacts are immutable as well. A retry must never hide
    # a same-identity legacy ZIP behind a newly sealed directory.
    if (dist / (name + '.zip')).exists() or (dist / (name + '.manifest.json')).exists():
        raise ValueError('Legacy artifact already uses this identity; preserve it and choose a new identity')
    lock.mkdir()
    locked = True
    if release.exists() or release.is_symlink():
        if release.is_symlink() or not release.is_dir():
            raise ValueError('Sealed output is not a release directory')
        old_manifest = json.loads((release / (name + '.manifest.json')).read_text())
        old_archive = release / (name + '.zip')
        if old_manifest != manifest or digest(old_archive) != expected_sha \
            or old_archive.stat().st_size != manifest['archive']['length'] \
            or app_tree(release / 'QuotaView.app') != manifest['appTreeSHA256']:
            raise ValueError('Sealed identity already exists with different bytes or evidence')
        print('Reused verified sealed unit:', release)
    else:
        # Keep the rename on one filesystem and promote App/ZIP/manifest together.
        candidate = Path(tempfile.mkdtemp(prefix='.' + name + '.seal-', dir=dist))
        shutil.move(str(app), candidate / 'QuotaView.app')
        shutil.move(str(archive), candidate / (name + '.zip'))
        (candidate / (name + '.manifest.json')).write_text(json.dumps(manifest, indent=2) + '\n')
        if digest(candidate / (name + '.zip')) != expected_sha \
            or app_tree(candidate / 'QuotaView.app') != manifest['appTreeSHA256']:
            raise ValueError('Candidate changed while preparing sealed unit')
        os.rename(candidate, release)
        candidate = None
        print('Sealed release unit:', release)
except (OSError, ValueError, KeyError) as error:
    print('Cannot seal release:', error, file=sys.stderr)
    sys.exit(4)
finally:
    if candidate is not None:
        shutil.rmtree(candidate)
    if locked:
        lock.rmdir()
PY
destination_zip_sha256="$(shasum -a 256 "${destination_zip}" | awk '{print $1}')"
# AUDIT-027: END SEAL

print "Built ${destination_app}"
print "Archived ${destination_zip}"
print "Manifest ${destination_manifest}"
print "Architectures: ${architectures}"
print "Widget architectures: ${widget_architectures}"
print "SHA-256: ${destination_zip_sha256}"

if [[ "${signing_identity}" == "-" ]]; then
    print "Signature: ad-hoc without Hardened Runtime"
    print "Warning: this signature has no trusted developer identity."
else
    print "Signature: ${signing_common_name} (${signing_identity})"
fi

if [[ -n "${notary_profile}" ]]; then
    print "Notarization: accepted and stapled"
else
    print "Notarization: not performed"
fi

if [[ "${is_developer_id}" == true ]]; then
    print \
        "Sparkle enclosure: sparkle:edSignature=\"${sparkle_signature}\" " \
        "length=\"${sparkle_archive_length}\""
fi
