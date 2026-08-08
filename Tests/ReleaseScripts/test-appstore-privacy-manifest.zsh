#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h:h}"
checker="${project_dir}/scripts/check-appstore-privacy-manifest.sh"
source_manifest="${project_dir}/Support/PrivacyInfo.xcprivacy"
fixture_root="$(/usr/bin/mktemp -d /private/tmp/quotaview-privacy-tests.XXXXXX)"
trap '/bin/rm -rf -- "${fixture_root}"' EXIT

expect_failure() {
    local expected="$1"
    local fixture="$2"
    local output
    if output="$("${checker}" "${fixture}" 2>&1)"; then
        print -u2 "Expected privacy manifest check to fail: ${expected}"
        exit 1
    fi
    [[ "${output}" == *"${expected}"* ]] || {
        print -u2 "Unexpected privacy manifest failure: ${output}"
        exit 1
    }
}

expect_source_failure() {
    local expected="$1"
    local source_root="$2"
    local output
    if output="$(
        QUOTAVIEW_PRIVACY_SOURCE_ROOT="${source_root}" \
            "${checker}" "${source_manifest}" 2>&1
    )"; then
        print -u2 "Expected privacy source check to fail: ${expected}"
        exit 1
    fi
    [[ "${output}" == *"${expected}"* ]] || {
        print -u2 "Unexpected privacy source failure: ${output}"
        exit 1
    }
}

"${checker}" "${source_manifest}" >/dev/null

tracking_fixture="${fixture_root}/tracking.xcprivacy"
/bin/cp "${source_manifest}" "${tracking_fixture}"
/usr/bin/plutil -replace NSPrivacyTracking -bool true "${tracking_fixture}"
expect_failure "Privacy tracking" "${tracking_fixture}"

collected_fixture="${fixture_root}/collected.xcprivacy"
/bin/cp "${source_manifest}" "${collected_fixture}"
/usr/bin/plutil -insert NSPrivacyCollectedDataTypes.0 \
    -string "unexpected" "${collected_fixture}"
expect_failure "Collected data type count" "${collected_fixture}"

wrong_defaults_fixture="${fixture_root}/wrong-defaults.xcprivacy"
/bin/cp "${source_manifest}" "${wrong_defaults_fixture}"
/usr/libexec/PlistBuddy -c \
    'Set :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:0 1C8F.1' \
    "${wrong_defaults_fixture}" >/dev/null
expect_failure "UserDefaults reason" "${wrong_defaults_fixture}"

wrong_file_fixture="${fixture_root}/wrong-file.xcprivacy"
/bin/cp "${source_manifest}" "${wrong_file_fixture}"
/usr/libexec/PlistBuddy -c \
    'Set :NSPrivacyAccessedAPITypes:1:NSPrivacyAccessedAPITypeReasons:0 C617.1' \
    "${wrong_file_fixture}" >/dev/null
expect_failure "FileTimestamp reason" "${wrong_file_fixture}"

unknown_category_fixture="${fixture_root}/unknown-category.xcprivacy"
/bin/cp "${source_manifest}" "${unknown_category_fixture}"
/usr/libexec/PlistBuddy -c \
    'Set :NSPrivacyAccessedAPITypes:1:NSPrivacyAccessedAPIType NSPrivacyAccessedAPICategorySystemBootTime' \
    "${unknown_category_fixture}" >/dev/null
expect_failure \
    "unsupported or unaudited Required Reason API category" \
    "${unknown_category_fixture}"

duplicate_fixture="${fixture_root}/duplicate.xcprivacy"
/bin/cp "${source_manifest}" "${duplicate_fixture}"
/usr/libexec/PlistBuddy -c \
    'Set :NSPrivacyAccessedAPITypes:1:NSPrivacyAccessedAPIType NSPrivacyAccessedAPICategoryUserDefaults' \
    "${duplicate_fixture}" >/dev/null
/usr/libexec/PlistBuddy -c \
    'Set :NSPrivacyAccessedAPITypes:1:NSPrivacyAccessedAPITypeReasons:0 CA92.1' \
    "${duplicate_fixture}" >/dev/null
expect_failure "UserDefaults category is duplicated" "${duplicate_fixture}"

unaudited_source_root="${fixture_root}/unaudited-source"
/bin/mkdir -p "${unaudited_source_root}"
print -r -- \
    'let uptime = ProcessInfo.processInfo.systemUptime' \
    > "${unaudited_source_root}/Probe.swift"
expect_source_failure \
    "source references an unaudited Required Reason API category" \
    "${unaudited_source_root}"

shared_defaults_root="${fixture_root}/shared-defaults-source"
/bin/mkdir -p "${shared_defaults_root}"
print -r -- \
    'let defaults = UserDefaults(suiteName: "group.example")' \
    > "${shared_defaults_root}/Probe.swift"
expect_source_failure \
    "App Group UserDefaults requires a separately audited 1C8F.1 reason" \
    "${shared_defaults_root}"

print "App Store privacy manifest tests passed."
