#!/usr/bin/env bash
# Checks a library built by build-binding-lib.sh the way the Go binding uses it: Go (1.26.11 and later refuse LTO
# sections) links it and the binding's library tests pass with it, the only library in the binding's lib folder.
#   scripts/check-with-binding.sh <library> <idena-wasm-binding checkout>
# It works on a temporary copy of the checkout, which it leaves as it was, and gives the library the name the Go
# toolchain's platform links. It does not compare the binding's bindings.h with this commit's exported functions: a
# changed function still links when no test calls it. The workflows check the binding out at a fixed commit: move it
# with the binding when those functions change.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <library> <idena-wasm-binding checkout>" >&2
  exit 2
fi
library="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
binding="$2"

# Go 1.26.11 is the first to refuse LTO sections: an older Go would pass a library it should refuse.
version="$(go env GOVERSION)"
if [[ "${version}" != devel* ]] && ! printf '%s\n%s\n' go1.26.11 "${version}" | sort -C -V; then
  echo "${version} does not check LTO sections: use Go 1.26.11 or later" >&2
  exit 1
fi

case "$(go env GOOS)/$(go env GOARCH)" in
  linux/amd64) name=libidena_wasm_linux_amd64.a ;;
  linux/arm64) name=libidena_wasm_linux_aarch64.a ;;
  darwin/amd64) name=libidena_wasm_darwin_amd64.a ;;
  darwin/arm64) name=libidena_wasm_darwin_arm64.a ;;
  windows/amd64) name=libidena_wasm_windows_amd64.a ;;
  *)
    echo "no binding library for $(go env GOOS)/$(go env GOARCH)" >&2
    exit 1
    ;;
esac

# A library named for another platform is refused: under this platform's name it would not link, or link wrong.
given="$(basename "${library}")"
if [[ "${given}" == libidena_wasm_*.a && "${given}" != "${name}" ]]; then
  echo "${given} is not this platform's library (${name})" >&2
  exit 1
fi

copy="$(mktemp -d)"
trap 'rm -rf "${copy}"' EXIT
# The checkout without its history and its own libraries.
(cd "${binding}" && tar -cf - --exclude=./.git --exclude='./lib/*.a' .) | (cd "${copy}" && tar -xf -)
cp "${library}" "${copy}/lib/${name}"
cd "${copy}"
GOTOOLCHAIN=local CGO_ENABLED=1 go test -count=1 ./tests -skip 'TestStaticLibraryArtifactChecksums'
