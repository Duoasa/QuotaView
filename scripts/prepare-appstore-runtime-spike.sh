#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
tool_dir="${project_dir}/Tools/AppStoreRuntimeSpike"

if [[ "$#" -ne 3 ]]; then
    print -u2 \
        "Usage: $0 <arm64-app-server> <x86_64-app-server> <output-directory>"
    exit 64
fi

arm64_runtime="$1"
x86_64_runtime="$2"
output_dir="$3"
universal_runtime="${output_dir}/QuotaViewCodexRuntime"
probe_host="${output_dir}/QuotaViewRuntimeSpikeHost"
module_cache_dir="${output_dir}/ModuleCache"
host_app="${output_dir}/QuotaViewRuntimeSpikeHost.app"
host_app_macos="${host_app}/Contents/MacOS"
host_app_helpers="${host_app}/Contents/Helpers"

for input in "${arm64_runtime}" "${x86_64_runtime}"; do
    if [[ ! -f "${input}" ]]; then
        print -u2 "Missing Runtime input: ${input}"
        exit 66
    fi
done

arm64_archs="$(xcrun lipo -archs "${arm64_runtime}")"
x86_64_archs="$(xcrun lipo -archs "${x86_64_runtime}")"
if [[ " ${arm64_archs} " != *" arm64 "* ]]; then
    print -u2 "Expected arm64 Runtime, found: ${arm64_archs}"
    exit 65
fi
if [[ " ${x86_64_archs} " != *" x86_64 "* ]]; then
    print -u2 "Expected x86_64 Runtime, found: ${x86_64_archs}"
    exit 65
fi

mkdir -p "${output_dir}" "${module_cache_dir}"
xcrun lipo \
    -create \
    "${arm64_runtime}" \
    "${x86_64_runtime}" \
    -output "${universal_runtime}"
chmod 0755 "${universal_runtime}"

xcrun swiftc \
    -parse-as-library \
    -swift-version 5 \
    -target arm64-apple-macos14.0 \
    -module-cache-path "${module_cache_dir}" \
    "${tool_dir}/RuntimeProbe.swift" \
    -o "${output_dir}/QuotaViewRuntimeSpikeHost-arm64"
xcrun swiftc \
    -parse-as-library \
    -swift-version 5 \
    -target x86_64-apple-macos14.0 \
    -module-cache-path "${module_cache_dir}" \
    "${tool_dir}/RuntimeProbe.swift" \
    -o "${output_dir}/QuotaViewRuntimeSpikeHost-x86_64"
xcrun lipo \
    -create \
    "${output_dir}/QuotaViewRuntimeSpikeHost-arm64" \
    "${output_dir}/QuotaViewRuntimeSpikeHost-x86_64" \
    -output "${probe_host}"
chmod 0755 "${probe_host}"

codesign \
    --force \
    --sign - \
    --identifier com.quotaview.appstore.runtime-spike.runtime \
    --options runtime \
    --timestamp=none \
    --entitlements "${tool_dir}/Runtime.entitlements" \
    "${universal_runtime}"
codesign \
    --force \
    --sign - \
    --identifier com.quotaview.appstore.runtime-spike.host \
    --options runtime \
    --timestamp=none \
    --entitlements "${tool_dir}/Host.entitlements" \
    "${probe_host}"

mkdir -p "${host_app_macos}" "${host_app_helpers}"
/bin/cp -f "${tool_dir}/Info.plist" "${host_app}/Contents/Info.plist"
/bin/cp -f "${probe_host}" "${host_app_macos}/QuotaViewRuntimeSpikeHost"
/bin/cp -f "${universal_runtime}" "${host_app_helpers}/QuotaViewCodexRuntime"
xattr -cr "${host_app}"
codesign \
    --force \
    --sign - \
    --identifier com.quotaview.appstore.runtime-spike.host \
    --options runtime \
    --timestamp=none \
    --entitlements "${tool_dir}/Host.entitlements" \
    "${host_app}"

runtime_archs="$(xcrun lipo -archs "${universal_runtime}")"
host_archs="$(xcrun lipo -archs "${probe_host}")"
if [[ " ${runtime_archs} " != *" arm64 "* ]] \
    || [[ " ${runtime_archs} " != *" x86_64 "* ]]; then
    print -u2 "Universal Runtime verification failed: ${runtime_archs}"
    exit 65
fi
if [[ " ${host_archs} " != *" arm64 "* ]] \
    || [[ " ${host_archs} " != *" x86_64 "* ]]; then
    print -u2 "Universal host verification failed: ${host_archs}"
    exit 65
fi

codesign --verify --strict --verbose=4 "${universal_runtime}"
codesign --verify --strict --verbose=4 "${probe_host}"
codesign --verify --deep --strict --verbose=4 "${host_app}"

runtime_sha256="$(shasum -a 256 "${universal_runtime}" | awk '{print $1}')"
host_sha256="$(shasum -a 256 "${probe_host}" | awk '{print $1}')"

print "runtime_path=${universal_runtime}"
print "runtime_archs=${runtime_archs}"
print "runtime_sha256=${runtime_sha256}"
print "host_path=${probe_host}"
print "host_archs=${host_archs}"
print "host_sha256=${host_sha256}"
print "host_app=${host_app}"
