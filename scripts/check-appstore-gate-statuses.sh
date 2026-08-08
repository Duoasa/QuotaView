#!/bin/zsh

set -euo pipefail

submission_mode="false"
if [[ "${1:-}" == "--submission" ]]; then
    submission_mode="true"
    shift
fi

if (( $# != 7 )); then
    print -u2 \
        "Usage: ${0:t} [--submission] app-price-status usage-snapshot-status plugin-status privacy-status privacy-url support-status support-url"
    exit 64
fi

app_price_status="$1"
usage_snapshot_status="$2"
plugin_status="$3"
privacy_status="$4"
privacy_url="$5"
support_status="$6"
support_url="$7"

fail() {
    print -u2 "App Store gate status check failed: $1"
    exit 2
}

require_known_status() {
    local label="$1"
    local actual="$2"
    shift 2
    local expected
    for expected in "$@"; do
        [[ "${actual}" == "${expected}" ]] && return 0
    done
    fail "${label} has unsupported value '${actual}'"
}

require_known_status \
    "App Store paid-download price status" \
    "${app_price_status}" pending configured
require_known_status \
    "Codex sanitized usage snapshot status" \
    "${usage_snapshot_status}" implemented validated
require_known_status \
    "Codex plugin distribution status" \
    "${plugin_status}" candidate released
require_known_status \
    "Privacy policy status" "${privacy_status}" draft published
require_known_status \
    "Support page status" "${support_status}" draft published

validate_published_url() {
    local label="$1"
    local publication_status="$2"
    local url="$3"
    [[ "${publication_status}" == "published" ]] || return 0
    [[ "${url}" == https://* ]] \
        || fail "the published ${label} URL must use HTTPS"
    [[ "${url}" != *'['* && "${url}" != *']'* ]] \
        || fail "the published ${label} URL contains a placeholder"
    [[ "${url}" != *' '* && "${url}" != *$'\t'* ]] \
        || fail "the published ${label} URL contains whitespace"
    [[ "${url}" != https://*@* ]] \
        || fail "the published ${label} URL contains user information"
}

validate_published_url "privacy policy" "${privacy_status}" "${privacy_url}"
validate_published_url "support page" "${support_status}" "${support_url}"

if [[ "${submission_mode}" == "true" ]]; then
    [[ "${app_price_status}" == "configured" ]] \
        || fail "the paid app price is not configured in App Store Connect"
    [[ "${usage_snapshot_status}" == "validated" ]] \
        || fail "the sanitized Codex usage snapshot validation is incomplete"

    [[ "${plugin_status}" == "released" ]] \
        || fail "the Codex plugin fresh-environment release validation is incomplete"
    [[ "${privacy_status}" == "published" ]] \
        || fail "the privacy policy is not published"
    [[ "${support_status}" == "published" ]] \
        || fail "the support page is not published"
fi

print \
    "App Store gate statuses passed: paid app price ${app_price_status}; sanitized usage snapshot ${usage_snapshot_status}; plugin ${plugin_status}; privacy ${privacy_status}; support ${support_status}."
