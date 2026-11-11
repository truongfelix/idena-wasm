#!/usr/bin/env bash
# Builds the static library the Go binding links (idena-wasm-binding lib/), for one Rust target, into OUTPUT.
#   scripts/build-binding-lib.sh <rust target, or "" for the host> <output file>
# Run it with Rust 1.97.0 and its llvm-tools component (rustup component add llvm-tools --toolchain 1.97.0).
#
# The same sources give the same bytes on any machine with the same target:
# - CARGO_HOME is a fixed folder: rustc writes the absolute paths of the dependencies' sources (panic locations)
#   into the library, and they sit under CARGO_HOME.
# - The LTO sections are removed (.llvmbc and .llvmcmd, Mach-O __LLVM): Rust's static libraries carry them, and Go
#   1.26.11 and later refuse any cgo library that does ("disallowed LTO section").
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <rust target or \"\"> <output file>" >&2
  exit 2
fi
target="$1"
output="$2"

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) export CARGO_HOME='C:\idena-cargo' ;;
  *) export CARGO_HOME=/tmp/idena-cargo ;;
esac

args=(--locked --release --all-features)
built=target/release/libidena_wasm.a
if [[ -n "${target}" ]]; then
  args+=(--target "${target}")
  built="target/${target}/release/libidena_wasm.a"
fi
cargo build "${args[@]}"

sysroot="$(rustc --print sysroot)"
host="$(rustc -vV | sed -n 's/^host: //p')"
objcopy="${sysroot}/lib/rustlib/${host}/bin/llvm-objcopy"
if [[ ! -x "${objcopy}" && ! -x "${objcopy}.exe" ]]; then
  echo "llvm-objcopy not found in ${sysroot}: rustup component add llvm-tools" >&2
  exit 1
fi

cp "${built}" "${output}"
"${objcopy}" \
  --remove-section=.llvmbc --remove-section=.llvmcmd \
  --remove-section=__LLVM,__bitcode --remove-section=__LLVM,__cmdline \
  "${output}"
