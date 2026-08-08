#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
manifest="${1:-${project_dir}/Support/PrivacyInfo.xcprivacy}"
source_root="${QUOTAVIEW_PRIVACY_SOURCE_ROOT:-${project_dir}/Sources}"

if [[ -n "${2:-}" ]]; then
    print -u2 "Usage: ${0:t} [/path/to/PrivacyInfo.xcprivacy]"
    exit 64
fi

fail() {
    print -u2 "App Store privacy manifest check failed: $1"
    exit 2
}

plist_value() {
    local key="$1"
    /usr/bin/plutil -extract "${key}" raw -o - "${manifest}" 2>/dev/null
}

require_equal() {
    local label="$1"
    local actual="$2"
    local expected="$3"
    [[ "${actual}" == "${expected}" ]] \
        || fail "${label}: expected '${expected}', found '${actual}'"
}

[[ -f "${manifest}" ]] || fail "manifest does not exist: ${manifest}"
/usr/bin/plutil -lint "${manifest}" >/dev/null \
    || fail "manifest is not a valid property list: ${manifest}"

require_equal "Privacy tracking" "$(plist_value NSPrivacyTracking)" "false"
require_equal \
    "Tracking domain count" \
    "$(plist_value NSPrivacyTrackingDomains)" \
    "0"
require_equal \
    "Collected data type count" \
    "$(plist_value NSPrivacyCollectedDataTypes)" \
    "0"

accessed_count="$(plist_value NSPrivacyAccessedAPITypes)"
require_equal "Required Reason API category count" "${accessed_count}" "2"

user_defaults_seen="false"
file_timestamp_seen="false"

for (( index = 0; index < accessed_count; index += 1 )); do
    entry="NSPrivacyAccessedAPITypes.${index}"
    category="$(plist_value "${entry}.NSPrivacyAccessedAPIType")"
    reason_count="$(plist_value "${entry}.NSPrivacyAccessedAPITypeReasons")"
    require_equal \
        "${category} reason count" \
        "${reason_count}" \
        "1"
    reason="$(plist_value "${entry}.NSPrivacyAccessedAPITypeReasons.0")"

    case "${category}" in
        NSPrivacyAccessedAPICategoryUserDefaults)
            [[ "${user_defaults_seen}" == "false" ]] \
                || fail "UserDefaults category is duplicated"
            user_defaults_seen="true"
            require_equal "UserDefaults reason" "${reason}" "CA92.1"
            ;;
        NSPrivacyAccessedAPICategoryFileTimestamp)
            [[ "${file_timestamp_seen}" == "false" ]] \
                || fail "FileTimestamp category is duplicated"
            file_timestamp_seen="true"
            require_equal "FileTimestamp reason" "${reason}" "3B52.1"
            ;;
        *)
            fail "unsupported or unaudited Required Reason API category: ${category}"
            ;;
    esac
done

[[ "${user_defaults_seen}" == "true" ]] \
    || fail "UserDefaults category is missing"
[[ "${file_timestamp_seen}" == "true" ]] \
    || fail "FileTimestamp category is missing"

if [[ -d "${source_root}" ]]; then
    if /usr/bin/grep -R -n -E \
        'systemUptime|mach_absolute_time|volumeAvailableCapacity|volumeTotalCapacity|systemFreeSize|systemSize|statfs|statvfs|activeInputModes' \
        "${source_root}" >/dev/null; then
        fail \
            "source references an unaudited Required Reason API category"
    fi
    if /usr/bin/grep -R -n -E \
        'UserDefaults[[:space:]]*\([[:space:]]*suiteName' \
        "${source_root}" >/dev/null; then
        fail \
            "App Group UserDefaults requires a separately audited 1C8F.1 reason"
    fi
fi

print "App Store privacy manifest checks passed."
print "Required reasons: UserDefaults CA92.1; FileTimestamp 3B52.1"
