#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h:h}"
checker="${repo_root}/scripts/check-appstore-gate-statuses.sh"

expect_failure() {
    if "${checker}" "$@" >/dev/null 2>&1; then
        print -u2 "Expected gate check to fail: $*"
        exit 1
    fi
}

policy_url="https://example.com/privacy"
support_url="https://example.com/support"

"${checker}" \
    pending implemented candidate draft "${policy_url}" \
    draft "${support_url}" >/dev/null

expect_failure \
    unknown implemented candidate draft "${policy_url}" \
    draft "${support_url}"
expect_failure \
    pending unknown candidate draft "${policy_url}" \
    draft "${support_url}"
expect_failure \
    pending implemented unknown draft "${policy_url}" \
    draft "${support_url}"
expect_failure \
    pending implemented candidate unknown "${policy_url}" \
    draft "${support_url}"
expect_failure \
    pending implemented candidate draft "${policy_url}" \
    unknown "${support_url}"
expect_failure \
    pending implemented candidate published \
    "http://example.com/privacy" draft "${support_url}"
expect_failure \
    pending implemented candidate published \
    "https://example.com/[PRIVACY]" draft "${support_url}"
expect_failure \
    pending implemented candidate published \
    "https://user@example.com/privacy" draft "${support_url}"
expect_failure \
    pending implemented candidate draft "${policy_url}" \
    published "http://example.com/support"
expect_failure \
    pending implemented candidate draft "${policy_url}" \
    published "https://example.com/[SUPPORT]"
expect_failure \
    pending implemented candidate draft "${policy_url}" \
    published "https://user@example.com/support"

"${checker}" \
    --submission configured validated released published \
    "${policy_url}" published "${support_url}" >/dev/null

expect_failure \
    --submission pending validated released published \
    "${policy_url}" published "${support_url}"
expect_failure \
    --submission configured implemented released published \
    "${policy_url}" published "${support_url}"
expect_failure \
    --submission configured validated candidate published \
    "${policy_url}" published "${support_url}"
expect_failure \
    --submission configured validated released draft \
    "${policy_url}" published "${support_url}"
expect_failure \
    --submission configured validated released published \
    "${policy_url}" draft "${support_url}"

print "App Store gate status tests passed."
