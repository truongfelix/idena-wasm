# Idena Wasm

## Research disclaimer

This is experimental research software. I cannot guarantee its security, correctness, or fitness for any purpose. Use it at your own risk, take responsibility for your decisions, independently verify changes, and stay vigilant.

Static WebAssembly smart-contract runtime used by `idena-go` through
`idena-wasm-binding`. It wraps a compatibility fork of Wasmer and is inspired
by [CosmWasm wasmvm](https://github.com/CosmWasm/wasmvm).

[![CI](https://github.com/truongfelix/idena-wasm/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/truongfelix/idena-wasm/actions/workflows/ci.yml)
[![Build](https://github.com/truongfelix/idena-wasm/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/truongfelix/idena-wasm/actions/workflows/build.yml)

> This is a source and artifact-production repository, not a general Wasmer
> distribution and not a standalone smart-contract application. There are no
> published fork releases. Use it only with the matching binding and node pins.

## Runtime status

The crate targets Rust `1.97.0` and pins every Wasmer crate to commit
`45f9bccf49187be24874400067923abda4c037da` in
[`truongfelix/wasmer`](https://github.com/truongfelix/wasmer). The Go binding records
the exact idena-wasm and Wasmer revisions used for each checked-in archive.

### What was updated

- The Wasmer 2.3 compatibility fork was pruned to the compiler, universal
  engine, Singlepass, middleware, and type surfaces required by Idena.
- Runtime dependencies and protobuf support were refreshed, while the Wasmer
  revision and Cargo lockfile remain exact inputs.
- The Wasmer pin includes the rkyv 0.8 migration for RUSTSEC-2026-0235;
  the lockfile resolves rkyv 0.8.18 without an advisory exception.
- Rust formatting, clippy with warnings denied, tests, `cargo audit`, and locked
  builds run in CI.
- Release builds enable overflow checks and produce checksummed static archives
  for Linux x64/ARM64, macOS x64/ARM64, and Windows x64.
- Workflow actions and Rust toolchains are pinned for repeatable builds.

### Benefits

- Smaller runtime and dependency surface than an unrestricted Wasmer build.
- Reproducible, platform-specific archives that can be verified before entering
  the Go dependency chain.
- Current compiler checks catch undefined, deprecated, and unsafe legacy Rust
  patterns that the original toolchain accepted.

### Risks and tradeoffs

- Wasm execution is consensus-sensitive. A runtime, compiler, metering, ABI, or
  floating-point behavior change can produce different contract results across
  nodes. Never update this repository independently of the matching binding and
  `idena-go` revisions.
- This remains a heavily modified Wasmer 2.3 code line, not the latest Wasmer
  architecture. Security fixes must be backported and tested rather than
  assumed from current upstream releases.
- A successful unit test or `cargo audit` does not prove deterministic behavior
  for every contract. Compare known contract fixtures and node integration
  tests before distributing new archives.
- Wasmer's compiled metadata ABI is now version 2. Old compiled-module caches
  must be rebuilt from original Wasm. The runner compiles raw Wasm; this does
  not change the contract-argument format or prove node replay compatibility.
- Static archives are platform and architecture specific. Linking the wrong
  archive or mixing GNU/MSVC assumptions can fail at build time or, worse,
  produce an unreviewed runtime.

## Build and test

Install Rust `1.97.0`, then run:

```bash
cargo fmt --all -- --check
cargo clippy --locked --all-targets --all-features -- -D warnings
cargo test --locked --all-targets --all-features
cargo build --locked --release --all-features
```

The native archive is written to `target/release/libidena_wasm.a`. Use the
GitHub build matrix for release artifacts instead of copying one host's archive
to another platform.

## Artifact flow

1. Build all platforms from one reviewed idena-wasm commit.
2. Record the idena-wasm and Wasmer revisions and each SHA-256 checksum.
3. Import the artifacts with `idena-wasm-binding/scripts/update-wasm-artifacts.sh`.
4. Run the binding tests, binary secret scan, and the consuming idena-go test
   suite before advancing any node pin.
