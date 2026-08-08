#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
info_plist="${1:-${project_dir}/Support/Info.plist}"
app_config="${2:-${project_dir}/Configs/App.xcconfig}"

if [[ -n "${3:-}" ]]; then
    print -u2 \
        "Usage: ${0:t} [/path/to/Info.plist] [/path/to/App.xcconfig]"
    exit 64
fi

fail() {
    print -u2 "App Store URL security check failed: $1"
    exit 2
}

plist_value() {
    local key="$1"
    /usr/bin/plutil -extract "${key}" raw -o - "${info_plist}" 2>/dev/null
}

xcconfig_value() {
    local key="$1"
    /usr/bin/awk -F '=' -v key="${key}" '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }
        trim($1) == key {
            print trim($2)
            exit
        }
    ' "${app_config}"
}

require_equal() {
    local label="$1"
    local actual="$2"
    local expected="$3"
    [[ "${actual}" == "${expected}" ]] \
        || fail "${label}: expected '${expected}', found '${actual}'"
}

[[ -f "${info_plist}" ]] || fail "Info.plist does not exist: ${info_plist}"
[[ -f "${app_config}" ]] || fail "App xcconfig does not exist: ${app_config}"
/usr/bin/plutil -lint "${info_plist}" >/dev/null \
    || fail "Info.plist is invalid: ${info_plist}"

require_equal \
    "URL type count" \
    "$(plist_value CFBundleURLTypes)" \
    "1"
require_equal \
    "URL type identifier" \
    "$(plist_value CFBundleURLTypes.0.CFBundleURLName)" \
    "com.quotaview.menubar.pairing"
require_equal \
    "URL type role" \
    "$(plist_value CFBundleURLTypes.0.CFBundleTypeRole)" \
    "Editor"
require_equal \
    "URL scheme count" \
    "$(plist_value CFBundleURLTypes.0.CFBundleURLSchemes)" \
    "1"
require_equal \
    "URL scheme" \
    "$(plist_value CFBundleURLTypes.0.CFBundleURLSchemes.0)" \
    "quotaview"

for forbidden_key in \
    QuotaViewOpenAIOAuthClientID \
    QuotaViewOpenAIOAuthRedirectURI \
    QuotaViewOpenAIOAuthTokenEndpoint \
    QuotaViewOpenAIUsageEndpoint \
    QuotaViewOpenAIProfileEndpoint; do
    if /usr/bin/plutil -extract "${forbidden_key}" raw -o - \
        "${info_plist}" >/dev/null 2>&1; then
        fail "forbidden app-owned OpenAI key: ${forbidden_key}"
    fi
done

if /usr/bin/grep -E \
    'QUOTAVIEW_OPENAI_|auth\.openai\.com|backend-api/wham' \
    "${app_config}" >/dev/null; then
    fail "App xcconfig contains an app-owned OpenAI credential or endpoint"
fi

if /usr/bin/plutil -extract NSAppTransportSecurity raw -o - \
    "${info_plist}" >/dev/null 2>&1; then
    fail "ATS exceptions are forbidden; rely on the strict system defaults"
fi

print "App Store URL security checks passed."
print \
    "Custom callback: quotaview://pair (Editor); ATS exceptions: none"
