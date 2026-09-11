#!/bin/zsh
set -euo pipefail
export COPYFILE_DISABLE=1
console_dir="${0:A:h}"
project_dir="${console_dir:h:h}"
python3 "${console_dir}/prepare.py"
stage_dir="${console_dir}/.build/Workspace"
scratch_dir="${console_dir}/.build/SwiftBuild"
swift build --package-path "${stage_dir}" --scratch-path "${scratch_dir}" --product QuotaView -c debug
binary_dir="$(swift build --package-path "${stage_dir}" --scratch-path "${scratch_dir}" --show-bin-path -c debug)"
assembly_dir="$(mktemp -d "${TMPDIR:-/tmp/}quotaview-island-console-build.XXXXXX")"
trap 'rm -rf "${assembly_dir}"' EXIT
app_dir="${assembly_dir}/Island Text Console.app"
mkdir -p "${app_dir}/Contents/MacOS" "${app_dir}/Contents/Resources/Fonts" "${app_dir}/Contents/Frameworks"
cp "${binary_dir}/QuotaView" "${app_dir}/Contents/MacOS/IslandTextConsole"
cp "${project_dir}"/Resources/Fonts/*.ttf "${app_dir}/Contents/Resources/Fonts/"
if [[ -d "${binary_dir}/Sparkle.framework" ]]; then
    ditto --noextattr --norsrc "${binary_dir}/Sparkle.framework" "${app_dir}/Contents/Frameworks/Sparkle.framework"
    install_name_tool -add_rpath '@loader_path/../Frameworks' "${app_dir}/Contents/MacOS/IslandTextConsole"
fi
if [[ -d "${binary_dir}/QuotaView_QuotaView.bundle" ]]; then
    ditto --noextattr --norsrc "${binary_dir}/QuotaView_QuotaView.bundle" "${app_dir}/Contents/Resources/QuotaView_QuotaView.bundle"
fi
cp "${console_dir}/.build/Console-Info.plist" "${app_dir}/Contents/Info.plist"
cp "${console_dir}/.build/source-manifest.json" "${app_dir}/Contents/Resources/source-manifest.json"
# Only the freshly generated independent console, never installed apps/data.
xattr -cr "${app_dir}"
codesign --force --deep --sign - "${app_dir}"
codesign --verify --deep --strict "${app_dir}"
archive_name="IslandTextConsole.zip"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "${app_dir}" "${assembly_dir}/${archive_name}"
mkdir -p "${assembly_dir}/verify"
ditto -x -k --noextattr --norsrc "${assembly_dir}/${archive_name}" "${assembly_dir}/verify"
codesign --verify --deep --strict "${assembly_dir}/verify/Island Text Console.app"
mkdir -p "${console_dir}/dist"
cp "${assembly_dir}/${archive_name}" "${console_dir}/dist/${archive_name}.new"
mv "${console_dir}/dist/${archive_name}.new" "${console_dir}/dist/${archive_name}"
(cd "${console_dir}/dist" && shasum -a 256 "${archive_name}" > SHA256SUMS)
cp "${console_dir}/.build/source-manifest.json" "${console_dir}/dist/source-manifest.json"
print -r -- "已保存：${console_dir}/dist/${archive_name}"
print -r -- "打开：${console_dir}/Open Console.command"
