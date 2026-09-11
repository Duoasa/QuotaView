#!/bin/zsh
set -euo pipefail
console_dir="${0:A:h}"
mode="${1:-}"
if [[ -n "${mode}" && "${mode}" != --rebuild && "${mode}" != --verify-only ]]; then
    print -u2 '用法：Open Console.command [--rebuild | --verify-only]'
    exit 2
fi
if [[ "${mode}" == --rebuild || ! -f "${console_dir}/dist/IslandTextConsole.zip" ]]; then
    zsh "${console_dir}/build.sh"
fi
cd "${console_dir}/dist"
shasum -a 256 -c SHA256SUMS
# Recreate the runtime from the saved archive; old /tmp builds are never required.
runtime_dir="$(mktemp -d "${TMPDIR:-/tmp/}quotaview-island-console-run.XXXXXX")"
ditto -x -k --noextattr --norsrc IslandTextConsole.zip "${runtime_dir}"
app_dir="${runtime_dir}/Island Text Console.app"
codesign --verify --deep --strict "${app_dir}"
if [[ "${mode}" == --verify-only ]]; then
    print -r -- '控制台归档、解包和签名检查通过。'
    rm -rf "${runtime_dir}"
else
    # Do not terminate an existing console or discard its current manual inputs.
    open -a "${app_dir}"
fi
