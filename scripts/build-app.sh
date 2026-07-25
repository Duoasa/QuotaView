#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
build_cache_root="${TMPDIR:-/tmp}/quotaview-swiftpm"
dist_dir="${project_dir}/dist"
info_plist="${project_dir}/Support/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")"
release_name="QuotaView-v${version}"
staging_dir="$(mktemp -d "/tmp/quotaview-package.XXXXXX")"
verification_dir="$(mktemp -d "/tmp/quotaview-verify.XXXXXX")"
staging_app="${staging_dir}/QuotaView.app"
destination_app="${dist_dir}/QuotaView.app"
staging_zip="${staging_dir}/${release_name}.zip"
destination_zip="${dist_dir}/${release_name}.zip"

cleanup() {
    rm -rf "${staging_dir}"
    rm -rf "${verification_dir}"
}
trap cleanup EXIT

mkdir -p \
    "${build_cache_root}/cache" \
    "${build_cache_root}/config" \
    "${build_cache_root}/security" \
    "${build_cache_root}/clang" \
    "${staging_app}/Contents/MacOS" \
    "${staging_app}/Contents/Resources" \
    "${dist_dir}"

swift_args=(
    --disable-sandbox
    --arch arm64
    --arch x86_64
    --cache-path "${build_cache_root}/cache"
    --config-path "${build_cache_root}/config"
    --security-path "${build_cache_root}/security"
    --scratch-path "${project_dir}/.build"
)

cd "${project_dir}"

CLANG_MODULE_CACHE_PATH="${build_cache_root}/clang" \
    swift build "${swift_args[@]}" -c release --product QuotaView

binary_dir="$(
    CLANG_MODULE_CACHE_PATH="${build_cache_root}/clang" \
        swift build "${swift_args[@]}" -c release --show-bin-path
)"

/bin/cp "${binary_dir}/QuotaView" "${staging_app}/Contents/MacOS/QuotaView"
/bin/cp "${info_plist}" "${staging_app}/Contents/Info.plist"

plutil -lint "${staging_app}/Contents/Info.plist"
xattr -cr "${staging_app}"
codesign --force --deep --sign - "${staging_app}"
codesign --verify --deep --strict "${staging_app}"

(
    cd "${staging_dir}"
    /usr/bin/zip -qry -X "${release_name}.zip" "QuotaView.app"
)

unzip -q "${staging_zip}" -d "${verification_dir}"
codesign --verify --deep --strict "${verification_dir}/QuotaView.app"

if [[ -d "${destination_app}" ]]; then
    previous_app="${dist_dir}/QuotaView.previous.$(date +%Y%m%d%H%M%S).app"
    mv "${destination_app}" "${previous_app}"
fi

mv "${staging_app}" "${destination_app}"
mv -f "${staging_zip}" "${destination_zip}"
xattr -cr "${destination_app}"

print "Built ${destination_app}"
print "Archived ${destination_zip}"
