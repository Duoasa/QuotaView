#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
build_cache_root="${TMPDIR:-/tmp}/codex-pulse-swiftpm"
dist_dir="${project_dir}/dist"
staging_dir="$(mktemp -d "/tmp/codex-pulse-package.XXXXXX")"
staging_app="${staging_dir}/CodexPulse.app"
destination_app="${dist_dir}/CodexPulse.app"
destination_zip="${dist_dir}/CodexPulse.zip"

cleanup() {
    rm -rf "${staging_dir}"
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
    --cache-path "${build_cache_root}/cache"
    --config-path "${build_cache_root}/config"
    --security-path "${build_cache_root}/security"
    --scratch-path "${project_dir}/.build"
)

cd "${project_dir}"

CLANG_MODULE_CACHE_PATH="${build_cache_root}/clang" \
    swift build "${swift_args[@]}" -c release --product CodexPulse

binary_dir="$(
    CLANG_MODULE_CACHE_PATH="${build_cache_root}/clang" \
        swift build "${swift_args[@]}" -c release --show-bin-path
)"

/bin/cp "${binary_dir}/CodexPulse" "${staging_app}/Contents/MacOS/CodexPulse"
/bin/cp "${project_dir}/Support/Info.plist" "${staging_app}/Contents/Info.plist"

plutil -lint "${staging_app}/Contents/Info.plist"
xattr -cr "${staging_app}"
codesign --force --deep --sign - "${staging_app}"
codesign --verify --deep --strict "${staging_app}"

(
    cd "${staging_dir}"
    /usr/bin/zip -qry -X "CodexPulse.zip" "CodexPulse.app"
)

if [[ -d "${destination_app}" ]]; then
    previous_app="${dist_dir}/CodexPulse.previous.$(date +%Y%m%d%H%M%S).app"
    mv "${destination_app}" "${previous_app}"
fi

mv "${staging_app}" "${destination_app}"
mv -f "${staging_dir}/CodexPulse.zip" "${destination_zip}"
codesign --verify --deep --strict "${destination_app}"

print "Built ${destination_app}"
print "Archived ${destination_zip}"
