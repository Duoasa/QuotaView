#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h:h}"
checker="${project_dir}/scripts/check-appstore-metadata.sh"
source_metadata="${project_dir}/docs/release/APP_STORE_METADATA_DRAFT.md"
fixture_root="$(/usr/bin/mktemp -d /private/tmp/quotaview-metadata-tests.XXXXXX)"
trap '/bin/rm -rf -- "${fixture_root}"' EXIT

expect_failure() {
    local expected="$1"
    local fixture="$2"
    shift 2
    local output_file="${fixture_root}/failure-output-${RANDOM}-${RANDOM}.log"
    local output exit_code

    set +e
    QUOTAVIEW_METADATA_FILE="${fixture}" \
        "${checker}" "$@" >"${output_file}" 2>&1
    exit_code=$?
    set -e
    output="$(/bin/cat "${output_file}")"

    if (( exit_code == 0 )); then
        print -u2 "Expected metadata check to fail: ${expected}"
        exit 1
    fi

    if [[ "${output}" != *"${expected}"* ]]; then
        print -u2 "Unexpected metadata failure: ${output}"
        exit 1
    fi
}

LC_ALL=en_US.UTF-8 "${checker}" >/dev/null
expect_failure \
    "submission metadata still contains a placeholder" \
    "${source_metadata}" \
    --submission

ready_fixture="${fixture_root}/ready.md"
/bin/cp "${source_metadata}" "${ready_fixture}"
/usr/bin/perl -0pi -e \
    's/Status: `Draft \/ Do Not Submit`/Status: `Ready`/; s/\[CONFIRM 2026 LEGAL OWNER\]/2026 Duoasa/; s/\[COMPLETE IN ACCOUNT\]/Completed/; s/\[COMPLETE IN APP STORE CONNECT\]/Provided securely/g' \
    "${ready_fixture}"
QUOTAVIEW_METADATA_FILE="${ready_fixture}" \
    "${checker}" --submission >/dev/null

long_subtitle_fixture="${fixture_root}/long-subtitle.md"
/bin/cp "${source_metadata}" "${long_subtitle_fixture}"
long_subtitle="1234567890123456789012345678901"
/usr/bin/perl -0pi -e \
    "s/AI Usage at a Glance/${long_subtitle}/" \
    "${long_subtitle_fixture}"
expect_failure \
    "English subtitle is 31 characters; maximum is 30" \
    "${long_subtitle_fixture}"

duplicate_keyword_fixture="${fixture_root}/duplicate-keyword.md"
/bin/cp "${source_metadata}" "${duplicate_keyword_fixture}"
/usr/bin/perl -0pi -e \
    's/usage,quota,credits/usage,quota,usage/' \
    "${duplicate_keyword_fixture}"
expect_failure \
    "English keywords contains duplicate term 'usage'" \
    "${duplicate_keyword_fixture}"

http_support_fixture="${fixture_root}/http-support.md"
/bin/cp "${source_metadata}" "${http_support_fixture}"
/usr/bin/perl -0pi -e \
    's#https://github\.com/Duoasa/QuotaView/blob/main/SUPPORT\.md#http://github.com/Duoasa/QuotaView/blob/main/SUPPORT.md#g' \
    "${http_support_fixture}"
expect_failure \
    "support URL must use HTTPS" \
    "${http_support_fixture}"

print "App Store metadata tests passed."
