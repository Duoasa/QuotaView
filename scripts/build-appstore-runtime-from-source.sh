#!/bin/zsh

set -euo pipefail

upstream_tag="rust-v0.146.1"
upstream_tag_object="abb1de9be901ab658fec7bbbc4a1fa2e85512be3"
upstream_commit="79b4f03d35962b005b007a015113b38930711665"
upstream_version="0.146.1"
rust_toolchain="1.95.0"
license_sha256="d17f227e4df5da1600391338865ce0f3055211760a36688f816941d58232d8dc"
source_lock_sha256="828175f2781fe6c83e3396194f1b00d7fab6b2a27017ea0daa896456c4079d77"
normalized_lock_sha256="15fce946a48df656e1f2496e7be9eab722c053fd6f8ba1fec1077931cb0c6a64"
workspace_lock_version_count="132"
rusty_v8_version="149.2.0"

download_verified() {
    local url="$1"
    local destination="$2"
    local expected_sha256="$3"
    local actual_sha256
    local temporary_download="${destination}.download"

    if [[ -f "${destination}" ]]; then
        actual_sha256="$(shasum -a 256 "${destination}" | awk '{print $1}')"
        if [[ "${actual_sha256}" == "${expected_sha256}" ]]; then
            return
        fi
    fi

    rm -f "${temporary_download}"
    curl --fail --location --silent --show-error \
        "${url}" \
        --output "${temporary_download}"
    actual_sha256="$(shasum -a 256 "${temporary_download}" | awk '{print $1}')"
    if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
        rm -f "${temporary_download}"
        print -u2 \
            "Downloaded asset SHA-256 mismatch: ${destination:t} (${actual_sha256})"
        exit 65
    fi
    mv "${temporary_download}" "${destination}"
}

if [[ "$#" -ne 2 ]]; then
    print -u2 "Usage: $0 <openai-codex-source> <output-directory>"
    exit 64
fi

source_dir="${1:A}"
output_dir="${2:A}"
codex_rust_dir="${source_dir}/codex-rs"

if [[ ! -d "${source_dir}/.git" ]] || [[ ! -f "${codex_rust_dir}/Cargo.lock" ]]; then
    print -u2 "Expected an OpenAI Codex checkout at ${source_dir}"
    exit 66
fi

actual_commit="$(git -C "${source_dir}" rev-parse HEAD)"
if [[ "${actual_commit}" != "${upstream_commit}" ]]; then
    print -u2 \
        "Upstream mismatch: expected ${upstream_commit}, found ${actual_commit}"
    exit 65
fi

tag_commit="$(git -C "${source_dir}" rev-list -n 1 "${upstream_tag}")"
if [[ "${tag_commit}" != "${upstream_commit}" ]]; then
    print -u2 "Tag ${upstream_tag} does not resolve to the locked commit."
    exit 65
fi
actual_tag_object="$(git -C "${source_dir}" rev-parse "${upstream_tag}")"
if [[ "${actual_tag_object}" != "${upstream_tag_object}" ]]; then
    print -u2 \
        "Tag object mismatch: expected ${upstream_tag_object}, found ${actual_tag_object}"
    exit 65
fi

source_status="$(git -C "${source_dir}" status --porcelain --untracked-files=normal)"
if [[ -n "${source_status}" ]] \
    && [[ "${source_status}" != " M codex-rs/Cargo.lock" ]]; then
    print -u2 "Unexpected source checkout changes:"
    print -u2 -- "${source_status}"
    exit 65
fi

if [[ ! -f "${source_dir}/LICENSE" ]] \
    || ! grep -q 'Apache License' "${source_dir}/LICENSE"; then
    print -u2 "OpenAI Codex Apache 2.0 license is missing."
    exit 65
fi
actual_license_sha256="$(shasum -a 256 "${source_dir}/LICENSE" | awk '{print $1}')"
if [[ "${actual_license_sha256}" != "${license_sha256}" ]]; then
    print -u2 "OpenAI Codex License SHA-256 mismatch: ${actual_license_sha256}"
    exit 65
fi

rustup_path="${RUSTUP_PATH:-$(command -v rustup || true)}"
if [[ ! -x "${rustup_path}" ]]; then
    print -u2 \
        "Rustup is required at ${rustup_path}; install toolchain ${rust_toolchain} first."
    exit 69
fi

for target in aarch64-apple-darwin x86_64-apple-darwin; do
    if ! "${rustup_path}" target list \
        --toolchain "${rust_toolchain}" \
        --installed | grep -qx "${target}"; then
        print -u2 \
            "Missing Rust target ${target} for toolchain ${rust_toolchain}."
        exit 69
    fi
done

lock_path="${codex_rust_dir}/Cargo.lock"
lock_sha256="$(shasum -a 256 "${lock_path}" | awk '{print $1}')"
case "${lock_sha256}" in
    "${source_lock_sha256}")
        placeholder_count="$(grep -c '^version = "0\.0\.0"$' "${lock_path}")"
        if [[ "${placeholder_count}" != "${workspace_lock_version_count}" ]]; then
            print -u2 \
                "Unexpected workspace placeholder count: ${placeholder_count}"
            exit 65
        fi
        # The upstream release workflow builds without --locked. At this tag,
        # Cargo only normalizes the 132 workspace package versions from the
        # development placeholder to the tag version. Apply that deterministic
        # normalization, then return to strict locked builds.
        sed -i '' \
            "s/^version = \"0\.0\.0\"$/version = \"${upstream_version}\"/" \
            "${lock_path}"
        ;;
    "${normalized_lock_sha256}")
        ;;
    *)
        print -u2 "Unexpected Cargo.lock SHA-256: ${lock_sha256}"
        exit 65
        ;;
esac

lock_sha256="$(shasum -a 256 "${lock_path}" | awk '{print $1}')"
if [[ "${lock_sha256}" != "${normalized_lock_sha256}" ]]; then
    print -u2 "Normalized Cargo.lock verification failed: ${lock_sha256}"
    exit 65
fi

mkdir -p "${output_dir}"
for target in aarch64-apple-darwin x86_64-apple-darwin; do
    case "${target}" in
        aarch64-apple-darwin)
            expected_arch="arm64"
            rusty_v8_archive_sha256="933b12ecdeb4b15150a69724810e8298d19b5a117070e016a55afb60929b2b5a"
            rusty_v8_binding_sha256="f0d0b199ec80f647b4fab01bc71947947588b6571eb11c08f946b8d8748c400b"
            rusty_v8_manifest_sha256="363ec3d2dcf568d9f6b8d7d1328e485acac9e67f962e94592f2fc41247a014ea"
            ;;
        x86_64-apple-darwin)
            expected_arch="x86_64"
            rusty_v8_archive_sha256="5b9e56155de4bf7121f82ad03ff13dffd787037102159b4218df936a95b672c4"
            rusty_v8_binding_sha256="f0d0b199ec80f647b4fab01bc71947947588b6571eb11c08f946b8d8748c400b"
            rusty_v8_manifest_sha256="adb70424db62b6d5f9ceb2237afd062190d6ceba7a6689d8b0aeac16417a9978"
            ;;
    esac
    rusty_v8_dir="${output_dir}/rusty-v8/${target}"
    rusty_v8_base_url="https://github.com/openai/codex/releases/download/rusty-v8-v${rusty_v8_version}"
    rusty_v8_archive="${rusty_v8_dir}/librusty_v8_release_${target}.a.gz"
    rusty_v8_binding="${rusty_v8_dir}/src_binding_release_${target}.rs"
    rusty_v8_checksums="${rusty_v8_dir}/rusty_v8_release_${target}.sha256"
    mkdir -p "${rusty_v8_dir}"
    download_verified \
        "${rusty_v8_base_url}/librusty_v8_release_${target}.a.gz" \
        "${rusty_v8_archive}" \
        "${rusty_v8_archive_sha256}"
    download_verified \
        "${rusty_v8_base_url}/src_binding_release_${target}.rs" \
        "${rusty_v8_binding}" \
        "${rusty_v8_binding_sha256}"
    download_verified \
        "${rusty_v8_base_url}/rusty_v8_release_${target}.sha256" \
        "${rusty_v8_checksums}" \
        "${rusty_v8_manifest_sha256}"
    if [[ "$(wc -l < "${rusty_v8_checksums}" | tr -d ' ')" != "2" ]]; then
        print -u2 "Unexpected rusty_v8 checksum manifest for ${target}."
        exit 65
    fi
    (
        cd "${rusty_v8_dir}"
        shasum -a 256 -c "${rusty_v8_checksums}"
    )

    (
        cd "${codex_rust_dir}"
        CARGO_NET_GIT_FETCH_WITH_CLI=true \
        CARGO_PROFILE_RELEASE_SPLIT_DEBUGINFO=packed \
        RUSTY_V8_ARCHIVE="${rusty_v8_archive}" \
        RUSTY_V8_SRC_BINDING_PATH="${rusty_v8_binding}" \
        "${rustup_path}" run "${rust_toolchain}" cargo build \
            --locked \
            --release \
            --target "${target}" \
            --package codex-app-server \
            --bin codex-app-server
    )

    built_runtime="${codex_rust_dir}/target/${target}/release/codex-app-server"
    if [[ ! -x "${built_runtime}" ]]; then
        print -u2 "Cargo did not produce ${built_runtime}"
        exit 65
    fi
    output_runtime="${output_dir}/codex-app-server-${target}"
    cp "${built_runtime}" "${output_runtime}"

    # Match OpenAI's macOS release workflow: keep split debug information in
    # the Cargo target directory and strip the executable copied for bundling.
    # The App Store bundle must not carry the much larger unstripped binary.
    strip -S -x "${output_runtime}"
    if [[ " $(xcrun lipo -archs "${output_runtime}") " != *" ${expected_arch} "* ]]; then
        print -u2 "Stripped Runtime architecture verification failed: ${target}"
        exit 65
    fi
done

print "upstream_tag=${upstream_tag}"
print "upstream_tag_object=${upstream_tag_object}"
print "upstream_commit=${upstream_commit}"
print "rust_toolchain=${rust_toolchain}"
print "license_sha256=${license_sha256}"
print "cargo_lock_sha256=${lock_sha256}"
print "rusty_v8_version=${rusty_v8_version}"
print "strip_policy=strip -S -x"
print "arm64_path=${output_dir}/codex-app-server-aarch64-apple-darwin"
print "x86_64_path=${output_dir}/codex-app-server-x86_64-apple-darwin"
