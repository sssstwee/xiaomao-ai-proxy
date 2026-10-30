#!/usr/bin/env bash
set -euo pipefail

# OHOS is checked against this compiler; do not inherit the desktop crate's toolchain.
export RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-1.92.0}"

# The default is verification only; release compilation is explicitly requested by setup.dart.
mode="${1:-check}"
case "$mode" in
  check|--check) cargo_action=check ;;
  build|--build) cargo_action=build ;;
  *) echo 'Usage: ohos_rust.sh [check|build]' >&2; exit 64 ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
harmony_native_sdk=''
for base in "${OHOS_NDK_HOME:-}" "${OHOS_SDK_HOME:-}" "${HOS_SDK_HOME:-}" "${DEVECO_SDK_HOME:-}" \
  "${HOME}/.local/share/harmony-cli/command-line-tools/sdk/default/openharmony"; do
  [[ -n "$base" ]] || continue
  for candidate in "$base/native" "$base/default/openharmony/native" "$base/openharmony/native"; do
    if [[ -x "$candidate/llvm/bin/aarch64-unknown-linux-ohos-clang" ]]; then
      harmony_native_sdk="$candidate"
      break 2
    fi
  done
done
if [[ -z "$harmony_native_sdk" ]]; then
  echo 'Set OHOS_NDK_HOME or HOS_SDK_HOME to an installed HarmonyOS SDK.' >&2
  exit 1
fi

export CC_aarch64_unknown_linux_ohos="$harmony_native_sdk/llvm/bin/aarch64-unknown-linux-ohos-clang"
export CXX_aarch64_unknown_linux_ohos="$harmony_native_sdk/llvm/bin/aarch64-unknown-linux-ohos-clang++"
export AR_aarch64_unknown_linux_ohos="$harmony_native_sdk/llvm/bin/llvm-ar"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="$CC_aarch64_unknown_linux_ohos"
export LIBCLANG_PATH="$harmony_native_sdk/llvm/lib"
export BINDGEN_EXTRA_CLANG_ARGS="${BINDGEN_EXTRA_CLANG_ARGS:-} --target=aarch64-linux-ohos --sysroot=\"$harmony_native_sdk/sysroot\" -D__MUSL__"

cargo_args=(--locked --manifest-path "$script_dir/../rust/Cargo.toml" --target aarch64-unknown-linux-ohos)
if [[ "$cargo_action" == build ]]; then cargo_args+=(--release); fi
exec cargo "$cargo_action" "${cargo_args[@]}"
