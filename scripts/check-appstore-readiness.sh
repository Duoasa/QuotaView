#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
project_file="${project_dir}/QuotaView.xcodeproj"
scheme="QuotaView"
submission_mode="false"

if [[ "${1:-}" == "--submission" ]]; then
    submission_mode="true"
elif [[ -n "${1:-}" ]]; then
    print -u2 "Usage: ${0:t} [--submission]"
    exit 64
fi

build_settings="$(
    xcodebuild \
        -project "${project_file}" \
        -scheme "${scheme}" \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -derivedDataPath \
            "/private/tmp/QuotaView-AppStore-readiness-derived-data" \
        -showBuildSettings 2>/dev/null
)"
target_setting() {
    local target="$1"
    local key="$2"
    print -r -- "${build_settings}" \
        | /usr/bin/awk -F ' = ' -v target="${target}" -v key="${key}" '
            $0 == "Build settings for action build and target " target ":" {
                active = 1
                next
            }
            /^Build settings for action build and target / {
                active = 0
            }
            active && $1 ~ "^[[:space:]]*" key "$" {
                print $2
                exit
            }
        '
}

setting() {
    local key="$1"
    target_setting "QuotaView" "${key}"
}

widget_setting() {
    local key="$1"
    target_setting "QuotaViewWidgetExtension" "${key}"
}

require_equal() {
    local label="$1"
    local actual="$2"
    local expected="$3"
    if [[ "${actual}" != "${expected}" ]]; then
        print -u2 "${label}: expected '${expected}', found '${actual}'"
        exit 2
    fi
}

release_channel="$(setting QUOTAVIEW_RELEASE_CHANNEL)"
marketing_version="$(setting MARKETING_VERSION)"
build_number="$(setting CURRENT_PROJECT_VERSION)"
sandbox_enabled="$(setting ENABLE_APP_SANDBOX)"
distribution_model="$(setting QUOTAVIEW_APP_DISTRIBUTION_MODEL)"
base_price_usd="$(setting QUOTAVIEW_APP_BASE_PRICE_USD)"
app_price_status="$(setting QUOTAVIEW_APP_PRICE_STATUS)"
plugin_status="$(setting QUOTAVIEW_CODEX_PLUGIN_DISTRIBUTION_STATUS)"
usage_snapshot_status="$(setting QUOTAVIEW_CODEX_USAGE_SNAPSHOT_STATUS)"
privacy_status="$(setting QUOTAVIEW_PRIVACY_POLICY_STATUS)"
privacy_url="$(setting QUOTAVIEW_PRIVACY_POLICY_URL)"
support_status="$(setting QUOTAVIEW_SUPPORT_STATUS)"
support_url="$(setting QUOTAVIEW_SUPPORT_URL)"

require_equal "Release channel" "${release_channel}" "appstore"
require_equal "App Sandbox" "${sandbox_enabled}" "YES"
require_equal \
    "App distribution model" \
    "${distribution_model}" \
    "paid-upfront"
require_equal "App base price (USD)" "${base_price_usd}" "4.99"
require_equal \
    "Widget bundle identifier" \
    "$(widget_setting PRODUCT_BUNDLE_IDENTIFIER)" \
    "com.quotaview.menubar.widget"
require_equal \
    "Widget Marketing Version" \
    "$(widget_setting MARKETING_VERSION)" \
    "${marketing_version}"
require_equal \
    "Widget Build Number" \
    "$(widget_setting CURRENT_PROJECT_VERSION)" \
    "${build_number}"
require_equal \
    "Widget App Sandbox" \
    "$(widget_setting ENABLE_APP_SANDBOX)" \
    "YES"
[[ "${marketing_version}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || {
    print -u2 "Marketing version must contain three numeric components."
    exit 2
}
[[ "${build_number}" =~ '^[1-9][0-9]*$' ]] || {
    print -u2 "Build number must be a positive integer."
    exit 2
}
/usr/bin/plutil -lint \
    "${project_dir}/Support/Info.plist" \
    "${project_dir}/Support/PrivacyInfo.xcprivacy" \
    "${project_dir}/Support/QuotaView.entitlements" \
    "${project_dir}/Support/QuotaViewWidget.entitlements" \
    "${project_dir}/Support/AppStoreExportOptions.plist" >/dev/null

"${project_dir}/scripts/check-appstore-url-security.sh" \
    "${project_dir}/Support/Info.plist" >/dev/null

for required_entitlement in \
    com.apple.security.app-sandbox \
    com.apple.security.files.user-selected.read-only; do
    /usr/libexec/PlistBuddy \
        -c "Print :${required_entitlement}" \
        "${project_dir}/Support/QuotaView.entitlements" \
        | /usr/bin/grep -q true || {
            print -u2 "Missing entitlement: ${required_entitlement}"
            exit 2
        }
done

require_equal \
    "App entitlement App Group" \
    "$(
        /usr/libexec/PlistBuddy \
            -c 'Print :com.apple.security.application-groups:0' \
            "${project_dir}/Support/QuotaView.entitlements"
    )" \
    "BUUH229D5Q.com.quotaview.shared"
require_equal \
    "Widget entitlement App Group" \
    "$(
        /usr/libexec/PlistBuddy \
            -c 'Print :com.apple.security.application-groups:0' \
            "${project_dir}/Support/QuotaViewWidget.entitlements"
    )" \
    "BUUH229D5Q.com.quotaview.shared"

for forbidden_entitlement in \
    com.apple.security.get-task-allow \
    com.apple.security.network.client \
    com.apple.security.network.server \
    com.apple.security.files.user-selected.read-write \
    com.apple.security.files.downloads.read-write; do
    if /usr/libexec/PlistBuddy \
        -c "Print :${forbidden_entitlement}" \
        "${project_dir}/Support/QuotaView.entitlements" \
        >/dev/null 2>&1; then
        print -u2 "Forbidden App entitlement: ${forbidden_entitlement}"
        exit 2
    fi
    if /usr/libexec/PlistBuddy \
        -c "Print :${forbidden_entitlement}" \
        "${project_dir}/Support/QuotaViewWidget.entitlements" \
        >/dev/null 2>&1; then
        print -u2 "Forbidden Widget entitlement: ${forbidden_entitlement}"
        exit 2
    fi
done

privacy_manifest="${project_dir}/Support/PrivacyInfo.xcprivacy"
"${project_dir}/scripts/check-appstore-privacy-manifest.sh" \
    "${privacy_manifest}" >/dev/null

gate_mode=()
[[ "${submission_mode}" == "true" ]] && gate_mode+=(--submission)
"${project_dir}/scripts/check-appstore-gate-statuses.sh" \
    "${gate_mode[@]}" \
    "${app_price_status}" \
    "${usage_snapshot_status}" \
    "${plugin_status}" \
    "${privacy_status}" \
    "${privacy_url}" \
    "${support_status}" \
    "${support_url}" >/dev/null

privacy_policy="${project_dir}/PRIVACY.md"
[[ -f "${privacy_policy}" ]] || {
    print -u2 "The QuotaView privacy policy document is missing."
    exit 2
}
if [[ "${submission_mode}" == "true" ]]; then
    if /usr/bin/grep -n -E \
        '\[(SUPPORT EMAIL|REQUIRED|OPTIONAL|TODO|PLACEHOLDER)[^]]*\]' \
        "${privacy_policy}" >/dev/null; then
        print -u2 "The privacy policy still contains a submission placeholder."
        exit 2
    fi
    if /usr/bin/grep -n -E \
        '^Status: Draft|^状态：.*草案' \
        "${privacy_policy}" >/dev/null; then
        print -u2 "The privacy policy is still marked as a draft."
        exit 2
    fi
fi

support_page="${project_dir}/SUPPORT.md"
[[ -f "${support_page}" ]] || {
    print -u2 "The QuotaView support document is missing."
    exit 2
}
if [[ "${submission_mode}" == "true" ]]; then
    if /usr/bin/grep -n -E \
        '\[(SUPPORT EMAIL|REQUIRED|OPTIONAL|TODO|PLACEHOLDER)[^]]*\]' \
        "${support_page}" >/dev/null; then
        print -u2 "The support page still contains a submission placeholder."
        exit 2
    fi
    if /usr/bin/grep -n -E \
        '^Status: Draft|^状态：.*草案' \
        "${support_page}" >/dev/null; then
        print -u2 "The support page is still marked as a draft."
        exit 2
    fi
fi

review_notes_file="${project_dir}/docs/release/APP_STORE_REVIEW_NOTES_DRAFT.md"
[[ -f "${review_notes_file}" ]] || {
    print -u2 "The App Review Notes document is missing."
    exit 2
}
review_notes_body="$(
    /usr/bin/awk '
        /^```text$/ && !active {
            active = 1
            next
        }
        active && /^```$/ {
            exit
        }
        active {
            print
        }
    ' "${review_notes_file}"
)"
[[ -n "${review_notes_body}" ]] || {
    print -u2 "The App Review Notes text block is missing or empty."
    exit 2
}
review_notes_bytes="$(
    print -rn -- "${review_notes_body}" \
        | /usr/bin/wc -c \
        | /usr/bin/tr -d '[:space:]'
)"
(( review_notes_bytes <= 4000 )) || {
    print -u2 \
        "The App Review Notes body is ${review_notes_bytes} bytes; Apple allows at most 4000."
    exit 2
}
if [[ "${submission_mode}" == "true" ]] \
    && print -r -- "${review_notes_body}" \
        | /usr/bin/grep -E \
            '\[(REVIEW ACCOUNT LOCATION|APPROVAL REFERENCE|REVIEW CONTACT)\]' \
            >/dev/null; then
    print -u2 "The App Review Notes still contain a submission placeholder."
    exit 2
fi

metadata_mode=()
[[ "${submission_mode}" == "true" ]] && metadata_mode+=(--submission)
"${project_dir}/scripts/check-appstore-metadata.sh" \
    "${metadata_mode[@]}" >/dev/null

if /usr/bin/grep -R -n -E \
    'Process\(|NSTask|auth\.json|hooks\.json|CodexAppServer|ActivityHelper|import[[:space:]]+WebKit|WKWebView|Sparkle|SUUpdater|NSAppleScript|ScriptingBridge|AXIsProcessTrusted|CGWindowListCreateImage' \
    "${project_dir}/Sources/QuotaView" \
    "${project_dir}/Sources/QuotaViewCore" >/dev/null; then
    print -u2 \
        "A forbidden Runtime, CLI, auth-file, Hook, WebKit, updater, automation, or capture path remains."
    exit 2
fi

if /usr/bin/grep -R -n -E \
    'auth\.openai\.com|backend-api/wham|ASWebAuthenticationSession|SecItem(Add|CopyMatching|Update|Delete)|QUOTAVIEW_OPENAI_' \
    "${project_dir}/Sources" \
    "${project_dir}/Configs" \
    "${project_dir}/Support" >/dev/null; then
    print -u2 \
        "An app-owned OpenAI OAuth, credential or private usage endpoint remains."
    exit 2
fi

print "QuotaView App Store readiness checks passed."
print "Version: ${marketing_version} (${build_number})"
print "Sanitized usage snapshot: ${usage_snapshot_status}; paid app price: ${app_price_status}; plugin: ${plugin_status}; privacy: ${privacy_status}; support: ${support_status}"
if [[ "${submission_mode}" != "true" ]]; then
    print "Submission gates were reported but not required."
fi
