#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
metadata_file="${QUOTAVIEW_METADATA_FILE:-${project_dir}/docs/release/APP_STORE_METADATA_DRAFT.md}"
app_config="${project_dir}/Configs/App.xcconfig"
submission_mode="false"

if [[ "${1:-}" == "--submission" ]]; then
    submission_mode="true"
elif [[ -n "${1:-}" ]]; then
    print -u2 "Usage: ${0:t} [--submission]"
    exit 64
fi

fail() {
    print -u2 "App Store metadata check failed: $1"
    exit 2
}

[[ -f "${metadata_file}" ]] \
    || fail "metadata file is missing: ${metadata_file}"
[[ -f "${app_config}" ]] \
    || fail "App xcconfig is missing: ${app_config}"

extract_xcconfig_value() {
    local key="$1"
    LC_ALL=C /usr/bin/awk -F '=' -v key="${key}" '
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

extract_table_value() {
    local field="$1"
    LC_ALL=C /usr/bin/awk -F '|' -v field="${field}" '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }
        trim($2) == field {
            value = trim($3)
            gsub(/^`|`$/, "", value)
            print value
            exit
        }
    ' "${metadata_file}"
}

extract_block() {
    local section="$1"
    local heading="$2"
    LC_ALL=C /usr/bin/awk -v section="${section}" -v heading="${heading}" '
        $0 == section {
            in_section = 1
            next
        }
        in_block && $0 == "```" {
            exit
        }
        in_block {
            print
            next
        }
        in_section && $0 ~ /^## / {
            exit
        }
        in_section && $0 == heading {
            found_heading = 1
            next
        }
        found_heading && $0 == "```text" {
            in_block = 1
        }
    ' "${metadata_file}"
}

character_count() {
    LC_ALL=en_US.UTF-8 /usr/bin/printf '%s' "$1" \
        | LC_ALL=en_US.UTF-8 /usr/bin/wc -m \
        | /usr/bin/tr -d '[:space:]'
}

byte_count() {
    /usr/bin/printf '%s' "$1" \
        | /usr/bin/wc -c \
        | /usr/bin/tr -d '[:space:]'
}

require_nonempty() {
    local label="$1"
    local value="$2"
    [[ -n "${value}" ]] || fail "${label} is missing or empty"
}

require_equal() {
    local label="$1"
    local actual="$2"
    local expected="$3"
    [[ "${actual}" == "${expected}" ]] \
        || fail "${label} must be '${expected}', found '${actual}'"
}

check_character_range() {
    local label="$1"
    local value="$2"
    local minimum="$3"
    local maximum="$4"
    local count
    count="$(character_count "${value}")"
    (( count >= minimum && count <= maximum )) \
        || fail "${label} is ${count} characters; allowed range is ${minimum}-${maximum}"
}

check_character_maximum() {
    local label="$1"
    local value="$2"
    local maximum="$3"
    local count
    count="$(character_count "${value}")"
    (( count <= maximum )) \
        || fail "${label} is ${count} characters; maximum is ${maximum}"
}

check_https_url() {
    local label="$1"
    local value="$2"
    require_nonempty "${label}" "${value}"
    [[ "${value}" == https://* ]] \
        || fail "${label} must use HTTPS"
    [[ "${value}" != *' '* && "${value}" != *$'\t'* ]] \
        || fail "${label} contains whitespace"
    [[ "${value}" != *'['* && "${value}" != *']'* ]] \
        || fail "${label} contains a placeholder"
    [[ "${value}" != https://*@* ]] \
        || fail "${label} contains user information"
}

check_keywords() {
    local label="$1"
    local value="$2"
    local bytes
    bytes="$(byte_count "${value}")"
    (( bytes <= 100 )) \
        || fail "${label} is ${bytes} bytes; maximum is 100"
    [[ "${value}" != *', '* && "${value}" != *$',\t'* ]] \
        || fail "${label} must not contain whitespace around commas"

    local -a terms
    terms=("${(@s:,:)value}")
    (( ${#terms} > 0 )) || fail "${label} is empty"

    local index comparison_index term comparison
    for (( index = 1; index <= ${#terms}; index++ )); do
        term="${terms[index]}"
        require_nonempty "${label} term ${index}" "${term}"
        (( $(character_count "${term}") > 2 )) \
            || fail "${label} term '${term}' must be longer than two characters"
        for (( comparison_index = index + 1; comparison_index <= ${#terms}; comparison_index++ )); do
            comparison="${terms[comparison_index]}"
            [[ "${term:l}" != "${comparison:l}" ]] \
                || fail "${label} contains duplicate term '${term}'"
        done
    done
}

app_name="$(extract_table_value "App Name")"
bundle_id="$(extract_table_value "Bundle ID")"
sku="$(extract_table_value "SKU")"
require_nonempty "App Name table value" "${app_name}"
require_equal \
    "App Name table value" \
    "${app_name}" \
    "$(extract_xcconfig_value PRODUCT_NAME)"
require_equal \
    "Bundle ID" \
    "${bundle_id}" \
    "$(extract_xcconfig_value PRODUCT_BUNDLE_IDENTIFIER)"
[[ "${sku}" == [A-Za-z0-9]* ]] \
    || fail "SKU must start with a letter or number"
[[ "${sku}" != *[^A-Za-z0-9._-]* ]] \
    || fail "SKU contains unsupported characters"

english_section="## 英文（English U.S.）"
chinese_section="## 简体中文（Simplified Chinese）"

english_name="$(extract_block "${english_section}" "### Name")"
english_subtitle="$(extract_block "${english_section}" "### Subtitle")"
english_promotional_text="$(extract_block "${english_section}" "### Promotional Text")"
english_description="$(extract_block "${english_section}" "### Description")"
english_keywords="$(extract_block "${english_section}" "### Keywords")"
english_support_url="$(extract_block "${english_section}" "### Support URL")"
english_marketing_url="$(extract_block "${english_section}" "### Marketing URL")"

chinese_name="$(extract_block "${chinese_section}" "### 名称")"
chinese_subtitle="$(extract_block "${chinese_section}" "### 副标题")"
chinese_promotional_text="$(extract_block "${chinese_section}" "### 宣传文本")"
chinese_description="$(extract_block "${chinese_section}" "### 描述")"
chinese_keywords="$(extract_block "${chinese_section}" "### 关键词")"
chinese_support_url="$(extract_block "${chinese_section}" "### 支持网址")"
chinese_marketing_url="$(extract_block "${chinese_section}" "### 营销网址")"

require_equal "English name" "${english_name}" "${app_name}"
require_equal "Simplified Chinese name" "${chinese_name}" "${app_name}"

check_character_range "English name" "${english_name}" 2 30
check_character_range "Simplified Chinese name" "${chinese_name}" 2 30
check_character_maximum "English subtitle" "${english_subtitle}" 30
check_character_maximum "Simplified Chinese subtitle" "${chinese_subtitle}" 30
check_character_maximum "English promotional text" "${english_promotional_text}" 170
check_character_maximum "Simplified Chinese promotional text" "${chinese_promotional_text}" 170
check_character_maximum "English description" "${english_description}" 4000
check_character_maximum "Simplified Chinese description" "${chinese_description}" 4000
check_keywords "English keywords" "${english_keywords}"
check_keywords "Simplified Chinese keywords" "${chinese_keywords}"
check_https_url "English support URL" "${english_support_url}"
check_https_url "Simplified Chinese support URL" "${chinese_support_url}"
check_https_url "English marketing URL" "${english_marketing_url}"
check_https_url "Simplified Chinese marketing URL" "${chinese_marketing_url}"
require_equal \
    "localized support URLs" \
    "${chinese_support_url}" \
    "${english_support_url}"
require_equal \
    "localized marketing URLs" \
    "${chinese_marketing_url}" \
    "${english_marketing_url}"

for field in \
    "${english_name}" \
    "${english_subtitle}" \
    "${english_promotional_text}" \
    "${english_description}" \
    "${english_keywords}" \
    "${chinese_name}" \
    "${chinese_subtitle}" \
    "${chinese_promotional_text}" \
    "${chinese_description}" \
    "${chinese_keywords}"; do
    [[ "${field}" != *'<'* && "${field}" != *'>'* ]] \
        || fail "localized plain-text metadata contains an HTML-like delimiter"
done

if [[ "${submission_mode}" == "true" ]]; then
    if /usr/bin/grep -n -E \
        '\[(CONFIRM|COMPLETE|REQUIRED|TODO|PLACEHOLDER)[^]]*\]' \
        "${metadata_file}" >/dev/null; then
        fail "submission metadata still contains a placeholder"
    fi
    if /usr/bin/grep -n -E \
        '^Status:.*(Draft|Do Not Submit)|^状态：.*草案' \
        "${metadata_file}" >/dev/null; then
        fail "submission metadata is still marked as a draft"
    fi
fi

print "QuotaView App Store metadata checks passed."
print \
    "English: name $(character_count "${english_name}")/30 chars; subtitle $(character_count "${english_subtitle}")/30; promotional $(character_count "${english_promotional_text}")/170; description $(character_count "${english_description}")/4000; keywords $(byte_count "${english_keywords}")/100 bytes."
print \
    "Simplified Chinese: name $(character_count "${chinese_name}")/30 chars; subtitle $(character_count "${chinese_subtitle}")/30; promotional $(character_count "${chinese_promotional_text}")/170; description $(character_count "${chinese_description}")/4000; keywords $(byte_count "${chinese_keywords}")/100 bytes."
if [[ "${submission_mode}" != "true" ]]; then
    print "Submission placeholders and draft status were reported but not required."
fi
