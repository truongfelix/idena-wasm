#!/usr/bin/env bash
# Builds the static library the Go binding links (idena-wasm-binding lib/), for one Rust target, into OUTPUT.
#   scripts/build-binding-lib.sh <rust target, or "" for the host> <output file>
# Run it with Rust 1.97.0 and its llvm-tools component (rustup component add llvm-tools --toolchain 1.97.0).
#
# - CARGO_HOME is one fixed folder, /var/tmp/idena-cargo (C:\idena-cargo on Windows): rustc writes the absolute
#   paths of the dependencies' sources (panic locations) into the library, and they sit under CARGO_HOME. With it, a
#   build of the same commit for the same target gives the same bytes on any machine (measured on linux x64: the
#   checkout's own folder does not show in the library). The folder must be the user's own and closed to others:
#   cargo builds the sources it finds already unpacked there.
# - The LTO sections are removed (.llvmbc and .llvmcmd, Mach-O __LLVM): Rust's static libraries carry them, and Go
#   1.26.11 and later refuse any cgo library that does ("disallowed LTO section"). The script checks that none is
#   left before it writes OUTPUT.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <rust target or \"\"> <output file>" >&2
  exit 2
fi
target="$1"
output="$2"

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) export CARGO_HOME='C:\idena-cargo' ;;
  *)
    export CARGO_HOME=/var/tmp/idena-cargo
    mkdir -p -m 700 "${CARGO_HOME}"
    if [[ ! -O "${CARGO_HOME}" ]]; then
      echo "${CARGO_HOME} belongs to another user: remove it or build as its owner" >&2
      exit 1
    fi
    chmod 700 "${CARGO_HOME}"
    ;;
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
tools="${sysroot}/lib/rustlib/${host}/bin"
if [[ ! -x "${tools}/llvm-objcopy" && ! -x "${tools}/llvm-objcopy.exe" ]]; then
  echo "llvm-objcopy not found in ${tools}: rustup component add llvm-tools" >&2
  exit 1
fi

stripped="$(mktemp "${output}.XXXXXX")"
trap 'rm -f "${stripped}"' EXIT
cp "${built}" "${stripped}"
"${tools}/llvm-objcopy" \
  --remove-section=.llvmbc --remove-section=.llvmcmd \
  --remove-section=__LLVM,__bitcode --remove-section=__LLVM,__cmdline \
  "${stripped}"
left="$("${tools}/llvm-objdump" --section-headers "${stripped}" |
  grep -cE '__LLVM|__bitcode|__cmdline|\.llvmbc|\.llvmcmd|\.gnu\.lto_|\.gnu\.debuglto_|\.llvm\.lto' || true)"
if [[ "${left}" != "0" ]]; then
  echo "${left} LTO sections left in the library" >&2
  exit 1
fi
mv "${stripped}" "${output}"
trap - EXIT
