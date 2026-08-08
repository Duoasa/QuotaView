#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h:h}"
checker="${project_dir}/scripts/check-appstore-url-security.sh"
source_plist="${project_dir}/Support/Info.plist"
source_config="${project_dir}/Configs/App.xcconfig"
fixture_root="$(/usr/bin/mktemp -d /private/tmp/quotaview-url-tests.XXXXXX)"
trap '/bin/rm -rf -- "${fixture_root}"' EXIT

expect_failure() {
    local expected="$1"
    local fixture="$2"
    local config="${3:-${source_config}}"
    local output
    if output="$("${checker}" "${fixture}" "${config}" 2>&1)"; then
        print -u2 "Expected URL security check to fail: ${expected}"
        exit 1
    fi
    [[ "${output}" == *"${expected}"* ]] || {
        print -u2 "Unexpected URL security failure: ${output}"
        exit 1
    }
}

"${checker}" "${source_plist}" >/dev/null

missing_role_fixture="${fixture_root}/missing-role.plist"
/bin/cp "${source_plist}" "${missing_role_fixture}"
/usr/libexec/PlistBuddy -c \
    'Delete :CFBundleURLTypes:0:CFBundleTypeRole' \
    "${missing_role_fixture}" >/dev/null
expect_failure "URL type role" "${missing_role_fixture}"

extra_scheme_fixture="${fixture_root}/extra-scheme.plist"
/bin/cp "${source_plist}" "${extra_scheme_fixture}"
/usr/libexec/PlistBuddy -c \
    'Add :CFBundleURLTypes:0:CFBundleURLSchemes:1 string unexpected' \
    "${extra_scheme_fixture}" >/dev/null
expect_failure "URL scheme count" "${extra_scheme_fixture}"

wrong_identifier_fixture="${fixture_root}/wrong-identifier.plist"
/bin/cp "${source_plist}" "${wrong_identifier_fixture}"
/usr/libexec/PlistBuddy -c \
    'Set :CFBundleURLTypes:0:CFBundleURLName example.invalid' \
    "${wrong_identifier_fixture}" >/dev/null
expect_failure "URL type identifier" "${wrong_identifier_fixture}"

oauth_key_fixture="${fixture_root}/oauth-key.plist"
/bin/cp "${source_plist}" "${oauth_key_fixture}"
/usr/libexec/PlistBuddy -c \
    'Add :QuotaViewOpenAIOAuthRedirectURI string quotaview://oauth/openai' \
    "${oauth_key_fixture}" >/dev/null
expect_failure "forbidden app-owned OpenAI key" "${oauth_key_fixture}"

oauth_config="${fixture_root}/oauth.xcconfig"
/bin/cp "${source_config}" "${oauth_config}"
/usr/bin/printf '%s\n' \
    'QUOTAVIEW_OPENAI_OAUTH_CLIENT_ID = forbidden' >> "${oauth_config}"
expect_failure \
    "App xcconfig contains" \
    "${source_plist}" \
    "${oauth_config}"

ats_fixture="${fixture_root}/ats-exception.plist"
/bin/cp "${source_plist}" "${ats_fixture}"
/usr/libexec/PlistBuddy -c \
    'Add :NSAppTransportSecurity dict' \
    "${ats_fixture}" >/dev/null
/usr/libexec/PlistBuddy -c \
    'Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true' \
    "${ats_fixture}" >/dev/null
expect_failure "ATS exceptions are forbidden" "${ats_fixture}"

print "App Store URL security tests passed."
