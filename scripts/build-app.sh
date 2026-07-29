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
if [[ "${build_number}" == "1" ]]; then
    release_name="QuotaView-v${version}"
else
    release_name="QuotaView-v${version}-build.${build_number}"
fi
staging_dir="$(mktemp -d "/tmp/quotaview-package.XXXXXX")"
verification_dir="$(mktemp -d "/tmp/quotaview-verify.XXXXXX")"
derived_data="${staging_dir}/DerivedData"
built_app="${derived_data}/Build/Products/${configuration}/QuotaView.app"
staging_app="${staging_dir}/QuotaView.app"
widget_extension="${staging_app}/Contents/PlugIns/QuotaViewWidgetExtension.appex"
destination_app="${dist_dir}/QuotaView.app"
staging_zip="${staging_dir}/${release_name}.zip"
destination_zip="${dist_dir}/${release_name}.zip"
signing_identity="${CODESIGN_IDENTITY:-}"
notary_profile="${NOTARY_PROFILE:-}"

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

signing_args=(
    --force
    --sign "${signing_identity}"
)

if [[ "${signing_identity}" == "-" ]]; then
    signing_args+=(--timestamp=none)
else
    signing_args+=(--options runtime --timestamp)
fi

for framework in "${staging_app}"/Contents/Frameworks/*.framework(N); do
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
if [[ "${signing_identity}" == "-" ]]; then
    if print -r -- "${signature_details}" | grep -q 'flags=.*runtime' \
        || print -r -- "${widget_signature_details}" \
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
            | grep -q 'flags=.*runtime'; then
        print -u2 \
            "Signed app or widget is missing the Hardened Runtime flag."
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

if [[ "${built_version}" != "${version}" ]] \
    || [[ "${built_build_number}" != "${build_number}" ]]; then
    print -u2 \
        "Version mismatch: expected ${version} (${build_number}), " \
        "built ${built_version} (${built_build_number})"
    exit 4
fi

if [[ "${widget_version}" != "${version}" ]] \
    || [[ "${widget_build_number}" != "${build_number}" ]]; then
    print -u2 \
        "Widget version mismatch: expected ${version} (${build_number}), " \
        "built ${widget_version} (${widget_build_number})"
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

app_entitlement_details="$(
    codesign -d --entitlements - "${staging_app}" 2>&1
)"
widget_entitlement_details="$(
    codesign -d --entitlements - "${widget_extension}" 2>&1
)"
if [[ "${app_entitlement_details}" \
        != *"group.com.quotaview.shared"* ]] \
    || [[ "${widget_entitlement_details}" \
        != *"group.com.quotaview.shared"* ]] \
    || [[ "${widget_entitlement_details}" \
        != *"com.apple.security.app-sandbox"* ]]; then
    print -u2 \
        "App Group or widget sandbox entitlements are missing."
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
for packaged_bundle in \
    "${destination_app}" \
    "${destination_app}"/Contents/Frameworks/*.framework(N) \
    "${destination_app}"/Contents/PlugIns/*.appex(N); do
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
