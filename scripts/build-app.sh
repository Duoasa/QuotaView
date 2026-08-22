#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
project_file="${project_dir}/QuotaView.xcodeproj"
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
app_group_identifier="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :QuotaViewAppGroupIdentifier' \
        "${info_plist}"
)"
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
destination_app="${dist_dir}/QuotaView.app"
staging_zip="${staging_dir}/${release_name}.zip"
destination_zip="${dist_dir}/${release_name}.zip"
signing_identity="${CODESIGN_IDENTITY:-}"
notary_profile="${NOTARY_PROFILE:-}"
sparkle_key_account="${SPARKLE_KEY_ACCOUNT:-com.quotaview.menubar}"

if [[ -z "${signing_identity}" ]]; then
    identity_inventory="$(security find-identity -v -p codesigning)"
    signing_identity="$(
        print -r -- "${identity_inventory}" \
            | sed -n 's/^[^"]*"\(Developer ID Application:[^"]*\)".*$/\1/p' \
            | head -n 1
    )"

    if [[ -z "${signing_identity}" ]]; then
        signing_identity="$(
            print -r -- "${identity_inventory}" \
                | sed -n 's/^[^"]*"\(Apple Development:[^"]*\)".*$/\1/p' \
                | head -n 1
        )"
    fi

    if [[ -z "${signing_identity}" ]]; then
        signing_identity="-"
    fi
fi

cleanup() {
    rm -rf "${staging_dir}"
    rm -rf "${verification_dir}"
}
trap cleanup EXIT

if [[ "${signing_identity}" != "-" ]]; then
    available_identities="$(security find-identity -v -p codesigning)"
    if [[ "${available_identities}" != *"${signing_identity}"* ]]; then
        print -u2 "Signing identity not found: ${signing_identity}"
        print -u2 "Install or repair the requested code signing identity first."
        exit 2
    fi
fi

if [[ -n "${notary_profile}" ]] \
    && [[ "${signing_identity}" != "Developer ID Application:"* ]]; then
    print -u2 "NOTARY_PROFILE requires a Developer ID Application signature."
    exit 2
fi

if [[ "${signing_identity}" == "Developer ID Application:"* ]] \
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

xcodebuild \
    -project "${project_file}" \
    -scheme "${scheme}" \
    -configuration "${configuration}" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "${derived_data}" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    clean build

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

if [[ -d "${destination_app}" ]]; then
    previous_app="${dist_dir}/QuotaView.previous.$(date +%Y%m%d%H%M%S).app"
    mv "${destination_app}" "${previous_app}"
fi

mv "${staging_app}" "${destination_app}"
mv -f "${staging_zip}" "${destination_zip}"

xattr -cr "${destination_app}"
destination_sparkle_version_dir="${destination_app}/Contents/Frameworks/"
destination_sparkle_version_dir+="Sparkle.framework/Versions/Current"
packaged_bundles=(
    "${destination_sparkle_version_dir}/XPCServices/Installer.xpc"
    "${destination_sparkle_version_dir}/XPCServices/Downloader.xpc"
    "${destination_sparkle_version_dir}/Updater.app"
    "${destination_app}"/Contents/Frameworks/*.framework(N)
    "${destination_app}"/Contents/PlugIns/*.appex(N)
    "${destination_app}"
)
for packaged_bundle in "${packaged_bundles[@]}"; do
    xattr -d com.apple.FinderInfo "${packaged_bundle}" 2>/dev/null || true
done
codesign \
    --verify \
    --deep \
    --strict \
    --verbose=4 \
    "${destination_app}"
destination_zip_sha256="$(
    shasum -a 256 "${destination_zip}" | awk '{print $1}'
)"
if [[ "${destination_zip_sha256}" != "${staging_zip_sha256}" ]]; then
    print -u2 "Release archive changed while moving into dist."
    exit 4
fi

if [[ "${signing_identity}" == "Developer ID Application:"* ]]; then
    sign_update_tool="$(
        find "${derived_data}/SourcePackages/artifacts" \
            -path '*/Sparkle/bin/sign_update' \
            -type f \
            -perm -111 \
            -print \
            -quit
    )"
    if [[ -z "${sign_update_tool}" ]]; then
        print -u2 "Sparkle sign_update tool was not resolved."
        exit 4
    fi

    sparkle_signature="$(
        "${sign_update_tool}" \
            --account "${sparkle_key_account}" \
            -p \
            "${destination_zip}"
    )"
    "${sign_update_tool}" \
        --account "${sparkle_key_account}" \
        --verify \
        "${destination_zip}" \
        "${sparkle_signature}"
    sparkle_archive_length="$(stat -f '%z' "${destination_zip}")"
fi

print "Built ${destination_app}"
print "Archived ${destination_zip}"
print "Architectures: ${architectures}"
print "Widget architectures: ${widget_architectures}"
print "SHA-256: ${destination_zip_sha256}"

if [[ "${signing_identity}" == "-" ]]; then
    print "Signature: ad-hoc without Hardened Runtime"
    print "Warning: this signature has no trusted developer identity."
else
    print "Signature: ${signing_identity}"
fi

if [[ -n "${notary_profile}" ]]; then
    print "Notarization: accepted and stapled"
else
    print "Notarization: not performed"
fi

if [[ "${signing_identity}" == "Developer ID Application:"* ]]; then
    print \
        "Sparkle enclosure: sparkle:edSignature=\"${sparkle_signature}\" " \
        "length=\"${sparkle_archive_length}\""
fi
