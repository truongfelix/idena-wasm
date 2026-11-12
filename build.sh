#!/usr/bin/env bash
# Builds the Windows library and the C header into a sibling idena-wasm-binding checkout (Git Bash on Windows).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
scripts/build-binding-lib.sh x86_64-pc-windows-gnu ../idena-wasm-binding/lib/libidena_wasm_windows_amd64.a
cbindgen --config cbindgen.toml --crate idena-wasm --output bindings.h
cp bindings.h ../idena-wasm-binding/lib/bindings.h
