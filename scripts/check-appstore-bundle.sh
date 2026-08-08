#!/bin/zsh

set -euo pipefail

submission_mode="false"
signature_mode="false"
if [[ "${1:-}" == "--signed" ]]; then
    signature_mode="true"
    shift
elif [[ "${1:-}" == "--submission" ]]; then
    submission_mode="true"
    signature_mode="true"
    shift
fi

app_path="${1:-}"
if [[ -z "${app_path}" || -n "${2:-}" ]]; then
    print -u2 \
        "Usage: ${0:t} [--signed|--submission] /path/to/QuotaView.app"
    exit 64
fi

project_dir="${0:A:h:h}"

fail() {
    print -u2 "App Store bundle check failed: $1"
    exit 2
}

require_equal() {
    local label="$1"
    local actual="$2"
    local expected="$3"
    if [[ "${actual}" != "${expected}" ]]; then
        fail "${label}: expected '${expected}', found '${actual}'"
    fi
}

plist_value() {
    local plist="$1"
    local key="$2"
    /usr/bin/plutil -extract "${key}" raw -o - "${plist}" 2>/dev/null
}

require_universal() {
    local label="$1"
    local binary="$2"
    [[ -f "${binary}" ]] || fail "missing ${label}: ${binary}"
    local architectures
    architectures="$(/usr/bin/lipo -archs "${binary}")"
    [[ " ${architectures} " == *" arm64 "* ]] \
        || fail "${label} is missing arm64: ${architectures}"
    [[ " ${architectures} " == *" x86_64 "* ]] \
        || fail "${label} is missing x86_64: ${architectures}"
}

entitlement_is_true() {
    local dump="$1"
    local key="$2"
    print -r -- "${dump}" | /usr/bin/awk -v key="${key}" '
        index($0, "[Key] " key) > 0 {
            found = 1
            next
        }
        found && index($0, "[Bool] true") > 0 {
            result = 1
            exit
        }
        found && index($0, "[Key] ") > 0 {
            exit
        }
        END {
            exit result == 1 ? 0 : 1
        }
    '
}

require_entitlement_true() {
    local label="$1"
    local dump="$2"
    local key="$3"
    entitlement_is_true "${dump}" "${key}" \
        || fail "${label} is missing entitlement ${key}=true"
}

require_entitlement_not_true() {
    local label="$1"
    local dump="$2"
    local key="$3"
    if entitlement_is_true "${dump}" "${key}"; then
        fail "${label} contains forbidden entitlement ${key}=true"
    fi
}

[[ -d "${app_path}" ]] || fail "App bundle does not exist: ${app_path}"

expected_build_number="$(
    /usr/bin/awk -F= '
        /^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=/ {
            value = $2
            gsub(/[[:space:]]/, "", value)
            print value
            exit
        }
    ' "${project_dir}/Configs/App.xcconfig"
)"
[[ "${expected_build_number}" =~ '^[1-9][0-9]*$' ]] \
    || fail "invalid CURRENT_PROJECT_VERSION in Configs/App.xcconfig"

info_plist="${app_path}/Contents/Info.plist"
widget_path="${app_path}/Contents/PlugIns/QuotaViewWidgetExtension.appex"
widget_info="${widget_path}/Contents/Info.plist"
privacy_manifest="${app_path}/Contents/Resources/PrivacyInfo.xcprivacy"

for plist in "${info_plist}" "${widget_info}" "${privacy_manifest}"; do
    [[ -f "${plist}" ]] || fail "missing plist: ${plist}"
    /usr/bin/plutil -lint "${plist}" >/dev/null \
        || fail "invalid plist: ${plist}"
done

privacy_manifest_count="$(
    /usr/bin/find "${app_path}" \
        -type f \
        -name PrivacyInfo.xcprivacy \
        | /usr/bin/wc -l \
        | /usr/bin/tr -d '[:space:]'
)"
require_equal \
    "Privacy manifest count" \
    "${privacy_manifest_count}" \
    "1"

"${0:A:h}/check-appstore-url-security.sh" \
    "${info_plist}" >/dev/null

marketing_version="$(plist_value "${info_plist}" CFBundleShortVersionString)"
build_number="$(plist_value "${info_plist}" CFBundleVersion)"
require_equal "App bundle identifier" \
    "$(plist_value "${info_plist}" CFBundleIdentifier)" \
    "com.quotaview.menubar"
require_equal "Marketing version" "${marketing_version}" "1.0.0"
require_equal \
    "Build number" \
    "${build_number}" \
    "${expected_build_number}"
require_equal "Release channel" \
    "$(plist_value "${info_plist}" QuotaViewReleaseChannel)" \
    "appstore"
require_equal "App Store category" \
    "$(plist_value "${info_plist}" LSApplicationCategoryType)" \
    "public.app-category.developer-tools"
require_equal "Minimum macOS version" \
    "$(plist_value "${info_plist}" LSMinimumSystemVersion)" \
    "14.0"
require_equal "App Group identifier" \
    "$(plist_value "${info_plist}" QuotaViewAppGroupIdentifier)" \
    "BUUH229D5Q.com.quotaview.shared"
require_equal "Distribution model" \
    "$(plist_value "${info_plist}" QuotaViewAppDistributionModel)" \
    "paid-upfront"
require_equal "Base price" \
    "$(plist_value "${info_plist}" QuotaViewAppBasePriceUSD)" \
    "4.99"
app_price_status="$(
    plist_value "${info_plist}" QuotaViewAppPriceStatus
)"
[[ "${app_price_status}" == "pending" \
    || "${app_price_status}" == "configured" ]] \
    || fail "the paid app price status is unsupported"
plugin_distribution_status="$(
    plist_value "${info_plist}" QuotaViewCodexPluginDistributionStatus
)"
[[ "${plugin_distribution_status}" == "candidate" \
    || "${plugin_distribution_status}" == "released" ]] \
    || fail "the Codex plugin distribution status is unsupported"
usage_snapshot_status="$(
    plist_value "${info_plist}" QuotaViewCodexUsageSnapshotStatus
)"
[[ "${usage_snapshot_status}" == "implemented" \
    || "${usage_snapshot_status}" == "validated" ]] \
    || fail "the Codex usage snapshot status is unsupported"
if [[ "${submission_mode}" == "true" ]]; then
    require_equal "Paid app price status" \
        "${app_price_status}" "configured"
    require_equal "Codex plugin distribution status" \
        "${plugin_distribution_status}" "released"
    require_equal "Codex usage snapshot status" \
        "${usage_snapshot_status}" "validated"
fi
for forbidden_key in \
    QuotaViewOpenAIOAuthClientID \
    QuotaViewOpenAIOAuthRedirectURI \
    QuotaViewOpenAIOAuthTokenEndpoint \
    QuotaViewOpenAIUsageEndpoint \
    QuotaViewOpenAIProfileEndpoint; do
    if /usr/bin/plutil -extract "${forbidden_key}" raw -o - \
        "${info_plist}" >/dev/null 2>&1; then
        fail "the bundle contains forbidden app-owned OpenAI key ${forbidden_key}"
    fi
done
require_equal "Export compliance declaration" \
    "$(plist_value "${info_plist}" ITSAppUsesNonExemptEncryption)" \
    "false"

privacy_policy_url="$(plist_value "${info_plist}" QuotaViewPrivacyPolicyURL)"
privacy_policy_status="$(plist_value "${info_plist}" QuotaViewPrivacyPolicyStatus)"
[[ "${privacy_policy_url}" == https://* ]] \
    || fail "the privacy policy URL must use HTTPS"
[[ "${privacy_policy_url}" != *'['* && "${privacy_policy_url}" != *']'* ]] \
    || fail "the privacy policy URL contains a placeholder"
[[ "${privacy_policy_url}" != https://*@* ]] \
    || fail "the privacy policy URL contains user information"
[[ "${privacy_policy_status}" == "draft" \
    || "${privacy_policy_status}" == "published" ]] \
    || fail "the privacy policy status is unsupported"
if [[ "${submission_mode}" == "true" ]]; then
    require_equal \
        "Privacy policy publication status" \
        "${privacy_policy_status}" \
        "published"
fi

support_url="$(plist_value "${info_plist}" QuotaViewSupportURL)"
support_status="$(plist_value "${info_plist}" QuotaViewSupportStatus)"
[[ "${support_url}" == https://* ]] \
    || fail "the support URL must use HTTPS"
[[ "${support_url}" != *'['* && "${support_url}" != *']'* ]] \
    || fail "the support URL contains a placeholder"
[[ "${support_url}" != https://*@* ]] \
    || fail "the support URL contains user information"
[[ "${support_status}" == "draft" \
    || "${support_status}" == "published" ]] \
    || fail "the support page status is unsupported"
if [[ "${submission_mode}" == "true" ]]; then
    require_equal \
        "Support page publication status" \
        "${support_status}" \
        "published"
fi

require_equal "Widget bundle identifier" \
    "$(plist_value "${widget_info}" CFBundleIdentifier)" \
    "com.quotaview.menubar.widget"
require_equal "Widget version" \
    "$(plist_value "${widget_info}" CFBundleShortVersionString)" \
    "${marketing_version}"
require_equal "Widget build number" \
    "$(plist_value "${widget_info}" CFBundleVersion)" \
    "${build_number}"
require_equal "Widget extension point" \
    "$(plist_value "${widget_info}" NSExtension.NSExtensionPointIdentifier)" \
    "com.apple.widgetkit-extension"

for resource in AppIcon.icns Assets.car PrivacyInfo.xcprivacy; do
    [[ -f "${app_path}/Contents/Resources/${resource}" ]] \
        || fail "missing packaged resource: ${resource}"
done

"${0:A:h}/check-appstore-privacy-manifest.sh" \
    "${privacy_manifest}" >/dev/null

require_universal \
    "QuotaView executable" \
    "${app_path}/Contents/MacOS/QuotaView"
require_universal \
    "Widget executable" \
    "${widget_path}/Contents/MacOS/QuotaViewWidgetExtension"

frameworks=("${app_path}"/Contents/Frameworks/*.framework(N))
(( ${#frameworks[@]} > 0 )) \
    || fail "the app contains no embedded QuotaView framework"
for framework in "${frameworks[@]}"; do
    framework_name="${framework:t:r}"
    require_universal \
        "${framework_name} framework" \
        "${framework}/Versions/Current/${framework_name}"
done

for pattern in \
    '*.storekit' \
    '*.xctest' \
    '*ActivityHook*' \
    '*CodexAppServer*' \
    '*QuotaViewProbe*' \
    '*Runtime*' \
    '*Sparkle*'; do
    match="$(/usr/bin/find "${app_path}" -iname "${pattern}" -print -quit)"
    [[ -z "${match}" ]] \
        || fail "forbidden packaged item matches ${pattern}: ${match}"
done

if [[ "${signature_mode}" == "true" ]]; then
    /usr/bin/codesign --verify --deep --strict "${app_path}" \
        || fail "the signed bundle signature is invalid"

    signature_details="$(
        /usr/bin/codesign -dv --verbose=4 "${app_path}" 2>&1
    )"
    [[ "${signature_details}" == *"TeamIdentifier=BUUH229D5Q"* ]] \
        || fail "the App Store signature has the wrong TeamIdentifier"
    [[ "${signature_details}" != *"Signature=adhoc"* ]] \
        || fail "the submission archive is ad-hoc signed"

    app_entitlement_dump="$(
        /usr/bin/codesign -d --entitlements - "${app_path}" 2>&1
    )"
    widget_entitlement_dump="$(
        /usr/bin/codesign -d --entitlements - "${widget_path}" 2>&1
    )"

    require_entitlement_true \
        "App" "${app_entitlement_dump}" com.apple.security.app-sandbox
    require_entitlement_true \
        "App" "${app_entitlement_dump}" \
        com.apple.security.files.user-selected.read-only
    require_entitlement_true \
        "Widget" "${widget_entitlement_dump}" \
        com.apple.security.app-sandbox

    for key in \
        com.apple.security.get-task-allow \
        com.apple.security.network.client \
        com.apple.security.network.server \
        com.apple.security.files.user-selected.read-write \
        com.apple.security.files.downloads.read-write; do
        require_entitlement_not_true \
            "App" "${app_entitlement_dump}" "${key}"
        require_entitlement_not_true \
            "Widget" "${widget_entitlement_dump}" "${key}"
    done

    for dump in "${app_entitlement_dump}" "${widget_entitlement_dump}"; do
        [[ "${dump}" == *"BUUH229D5Q.com.quotaview.shared"* ]] \
            || fail "App Group entitlement is missing or incorrect"
    done
fi

print "QuotaView App Store bundle checks passed."
print "Bundle: ${marketing_version} (${build_number}) / appstore"
print "Architectures: arm64 + x86_64"
if [[ "${submission_mode}" == "true" ]]; then
    print "Signature and submission entitlements: verified"
elif [[ "${signature_mode}" == "true" ]]; then
    print "Signature and sandbox entitlements: verified"
else
    print "Signature checks were skipped in non-submission mode."
fi
