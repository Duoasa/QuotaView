#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
project_file="${project_dir}/QuotaView.xcodeproj"
scheme="QuotaView"
configuration="Release"
dist_dir="${project_dir}/dist"
info_plist="${project_dir}/Support/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}")"
release_name="QuotaView-v${version}"
staging_dir="$(mktemp -d "/tmp/quotaview-package.XXXXXX")"
verification_dir="$(mktemp -d "/tmp/quotaview-verify.XXXXXX")"
derived_data="${staging_dir}/DerivedData"
built_app="${derived_data}/Build/Products/${configuration}/QuotaView.app"
staging_app="${staging_dir}/QuotaView.app"
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

signing_args=(
    --force
    --sign "${signing_identity}"
    --options runtime
)

if [[ "${signing_identity}" == "-" ]]; then
    signing_args+=(--timestamp=none)
else
    signing_args+=(--timestamp)
fi

for framework in "${staging_app}"/Contents/Frameworks/*.framework(N); do
    codesign "${signing_args[@]}" "${framework}"
done

for library in "${staging_app}"/Contents/Frameworks/*.dylib(N); do
    codesign "${signing_args[@]}" "${library}"
done

codesign "${signing_args[@]}" "${staging_app}"
codesign --verify --deep --strict --verbose=4 "${staging_app}"

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

if [[ "${built_version}" != "${version}" ]] \
    || [[ "${built_build_number}" != "${build_number}" ]]; then
    print -u2 \
        "Version mismatch: expected ${version} (${build_number}), " \
        "built ${built_version} (${built_build_number})"
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

if [[ " ${architectures} " != *" arm64 "* ]] \
    || [[ " ${architectures} " != *" x86_64 "* ]]; then
    print -u2 "Expected a universal binary, found: ${architectures}"
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
print "SHA-256: ${destination_zip_sha256}"

if [[ "${signing_identity}" == "-" ]]; then
    print "Signature: ad-hoc with Hardened Runtime"
    print "Warning: this signature has no trusted developer identity."
else
    print "Signature: ${signing_identity}"
fi

if [[ -n "${notary_profile}" ]]; then
    print "Notarization: accepted and stapled"
else
    print "Notarization: not performed"
fi
