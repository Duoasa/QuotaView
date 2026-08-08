#!/bin/zsh

set -euo pipefail

signed_local_mode="false"
if [[ "${1:-}" == "--signed-local" ]]; then
    signed_local_mode="true"
    shift
fi
if [[ -n "${1:-}" ]]; then
    print -u2 "Usage: ${0:t} [--signed-local]"
    exit 64
fi

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
project_file="${project_dir}/QuotaView.xcodeproj"
scheme="QuotaView"
output_root="${APPSTORE_OUTPUT_DIR:-${project_dir}/dist/appstore}"
archive_path="${output_root}/QuotaView.xcarchive"
export_path="${output_root}/export"
export_options="${project_dir}/Support/AppStoreExportOptions.plist"

if [[ "${signed_local_mode}" == "true" ]]; then
    "${script_dir}/check-appstore-readiness.sh"
else
    "${script_dir}/check-appstore-readiness.sh" --submission
fi
/bin/mkdir -p "${output_root}"

archive_args=(
    -project "${project_file}"
    -scheme "${scheme}"
    -configuration Release
    -destination "generic/platform=macOS"
    -archivePath "${archive_path}"
)
if [[ "${signed_local_mode}" != "true" ]]; then
    archive_args+=(-allowProvisioningUpdates)
fi
xcodebuild "${archive_args[@]}" clean archive

if [[ "${signed_local_mode}" == "true" ]]; then
    "${script_dir}/check-appstore-bundle.sh" \
        --signed \
        "${archive_path}/Products/Applications/QuotaView.app"
    print "Signed local archive: ${archive_path}"
    print "App Store export was intentionally skipped."
    exit 0
fi

"${script_dir}/check-appstore-bundle.sh" \
    --submission \
    "${archive_path}/Products/Applications/QuotaView.app"

xcodebuild \
    -exportArchive \
    -archivePath "${archive_path}" \
    -exportPath "${export_path}" \
    -exportOptionsPlist "${export_options}" \
    -allowProvisioningUpdates

"${script_dir}/check-appstore-export.sh" --submission "${export_path}"

print "Archive: ${archive_path}"
print "Export: ${export_path}"
