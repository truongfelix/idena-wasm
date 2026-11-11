#!/usr/bin/env bash
# Checks a library built by build-binding-lib.sh the way the Go binding uses it: Go (1.26.11 and later refuse LTO
# sections) links it and the binding's library tests pass with it, the only library in the binding's lib folder.
#   scripts/check-with-binding.sh <library> <idena-wasm-binding checkout>
# The workflows check the binding out at a fixed commit: move it with the binding when the library's exported
# functions change.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <library> <idena-wasm-binding checkout>" >&2
  exit 2
fi
library="$1"
binding="$2"

rm -f "${binding}"/lib/*.a
cp "${library}" "${binding}/lib/"
cd "${binding}"
GOTOOLCHAIN=local CGO_ENABLED=1 go test -count=1 ./tests \
  -skip 'TestStaticLibraryArtifactChecksums|TestWindowsStaticLibraryNativeDependencies'
