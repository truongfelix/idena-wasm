#!/usr/bin/env bash
# Builds the static library the Go binding links (idena-wasm-binding lib/), for one Rust target, into OUTPUT.
#   scripts/build-binding-lib.sh <rust target, or "" for the host> <output file>
# It needs Rust 1.97.0 with its llvm-tools component (both in rust-toolchain.toml: rustup installs them).
#
# - CARGO_HOME is one fixed folder, /var/tmp/idena-cargo: rustc writes the absolute paths of the dependencies'
#   sources (panic locations) into the library, and they sit under CARGO_HOME. With it, a build of the same commit for
#   the same target gives the same bytes on any Linux or macOS machine (measured on linux x64: the checkout's own
#   folder does not show in the library). The folder must be the user's own and closed to others:
#   cargo builds the sources it finds already unpacked there. The script refuses one that is a link or another user's
#   (on a shared machine, the first user to build owns it). On Windows the folder is %USERPROFILE%\idena-cargo,
#   private to the user: the same path on every CI runner, so a Windows build matches CI's only when built there.
#   The script does not read the user's own Cargo settings (~/.cargo/config.toml).
# - The library is built in the repository's own target folder, whatever CARGO_TARGET_DIR says.
# - The LTO sections are removed (.llvmbc and .llvmcmd, Mach-O __LLVM): Rust's static libraries carry them, and Go
#   1.26.11 and later refuse any cgo library that does ("disallowed LTO section"). The script checks that none is
#   left before it writes OUTPUT.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <rust target or \"\"> <output file>" >&2
  exit 2
fi
target="$1"
output="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"

# Settings that change the bytes are not taken from the environment: the build is the repository's (Cargo.toml,
# rust-toolchain.toml, .cargo/config.toml) and nothing else.
for name in RUSTFLAGS CARGO_ENCODED_RUSTFLAGS CARGO_BUILD_RUSTFLAGS RUSTC_WRAPPER RUSTC_WORKSPACE_WRAPPER RUSTC; do
  if [[ -n "${!name:-}" ]]; then
    echo "${name} is set: unset it, the library must build from the repository's own settings" >&2
    exit 1
  fi
done
if compgen -e | grep -qE '^CARGO_PROFILE_|^CARGO_TARGET_.*_RUSTFLAGS$'; then
  echo "a CARGO_PROFILE_* or CARGO_TARGET_*_RUSTFLAGS variable is set: unset it" >&2
  exit 1
fi
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo}"
export CARGO_TARGET_DIR="${repo}/target"

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) export CARGO_HOME="${USERPROFILE}\idena-cargo" ;;
  *)
    export CARGO_HOME=/var/tmp/idena-cargo
    if [[ -L "${CARGO_HOME}" ]]; then
      echo "${CARGO_HOME} is a link: remove it" >&2
      exit 1
    fi
    mkdir -p -m 700 "${CARGO_HOME}"
    if [[ -L "${CARGO_HOME}" || ! -O "${CARGO_HOME}" ]]; then
      echo "${CARGO_HOME} belongs to another user: remove it or build as its owner" >&2
      exit 1
    fi
    # Open to others once, it may hold sources someone else put there: refused, not closed again.
    mode="$(stat -c %a "${CARGO_HOME}" 2>/dev/null || stat -f %Lp "${CARGO_HOME}")"
    if [[ "${mode}" != "700" ]]; then
      echo "${CARGO_HOME} has mode ${mode}, not 700: remove it and build again" >&2
      exit 1
    fi
    ;;
esac

args=(--locked --release --all-features)
built="${CARGO_TARGET_DIR}/release/libidena_wasm.a"
if [[ -n "${target}" ]]; then
  args+=(--target "${target}")
  built="${CARGO_TARGET_DIR}/${target}/release/libidena_wasm.a"
fi
rustc_version="$(rustc --version)"
if [[ "${rustc_version}" != "rustc 1.97.0 "* ]]; then
  echo "${rustc_version}: the libraries are built with Rust 1.97.0 (rust-toolchain.toml)" >&2
  exit 1
fi
cargo build "${args[@]}"

sysroot="$(rustc --print sysroot)"
host="$(rustc -vV | sed -n 's/^host: //p')"
tools="${sysroot}/lib/rustlib/${host}/bin"
for tool in llvm-objcopy llvm-objdump; do
  if [[ ! -x "${tools}/${tool}" && ! -x "${tools}/${tool}.exe" ]]; then
    echo "${tool} not found in ${tools}: rustup component add llvm-tools" >&2
    exit 1
  fi
done

stripped="$(mktemp "${output}.XXXXXX")"
sections="$(mktemp)"
trap 'rm -f "${stripped}" "${sections}"' EXIT
cp "${built}" "${stripped}"
"${tools}/llvm-objcopy" \
  --remove-section=.llvmbc --remove-section=.llvmcmd \
  --remove-section=__LLVM,__bitcode --remove-section=__LLVM,__cmdline \
  "${stripped}"
# The section list is read on its own, so that a failed read stops the script instead of reading as "none left".
"${tools}/llvm-objdump" --section-headers "${stripped}" > "${sections}"
if ! grep -q '^Sections:' "${sections}"; then
  echo "llvm-objdump listed no section of ${stripped}" >&2
  exit 1
fi
"${tools}/llvm-objdump" --private-headers "${stripped}" >> "${sections}"
# Section names, and on Mach-O the segments as Go checks them (any __LLVM or __GNU_LTO segment is refused).
left="$(grep -cE '__LLVM|__bitcode|__cmdline|\.llvmbc|\.llvmcmd|\.gnu\.lto_|\.gnu\.debuglto_|\.llvm\.lto|segname __GNU_LTO' "${sections}" || true)"
if [[ "${left}" != "0" ]]; then
  echo "${left} LTO sections left in the library" >&2
  exit 1
fi
chmod 644 "${stripped}"
mv "${stripped}" "${output}"
trap - EXIT
rm -f "${sections}"
