#!/bin/zsh

set -euo pipefail

data_root="${1:-}"
expected_version="${2:-}"
expected_events="${3:-SessionStart,UserPromptSubmit,Stop,SessionEnd}"

if [[ -z "${data_root}" || -z "${expected_version}" || -n "${4:-}" ]]; then
    print -u2 \
        "Usage: ${0:t} /absolute/PLUGIN_DATA expected-version [expected-events]"
    exit 64
fi
[[ "${data_root}" == /* && -d "${data_root}" ]] || {
    print -u2 "The explicit PLUGIN_DATA directory is unavailable."
    exit 2
}

QUOTAVIEW_PLUGIN_DATA_E2E="${data_root}" \
QUOTAVIEW_PLUGIN_EXPECTED_VERSION="${expected_version}" \
QUOTAVIEW_PLUGIN_EXPECTED_EVENTS="${expected_events}" \
    swift test \
        --disable-sandbox \
        --filter \
        CodexPluginBridgeLiveTests.testExplicitLivePluginDirectoryUsesProductionReader

print "QuotaView live Codex plugin bridge check passed."
