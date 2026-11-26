# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-11-26

### Added

- Closed the remaining Go 1.24 to Go 1.27 gaps: `os.Root`, `runtime.AddCleanup`, `weak`, `unique`, `crypto/rand.Text`, post-quantum cryptography (`crypto/mlkem`, `crypto/mldsa`, `crypto/hpke`), FIPS 140-3, `http.CrossOriginProtection`, `sync.WaitGroup.Go`, `testing/cryptotest`, `strings.CutLast`, `bytes.CutLast`, self-referential generic constraints, promoted fields in struct literals, `slog.NewMultiHandler`, `slog.GroupAttrs`, `slog.DiscardHandler`, `encoding/json/v2` streaming entry points, and Go 1.26 and Go 1.27 `net/http` additions.
- Expanded synctest coverage in `testing.md`, including `synctest.Sleep` and `httptest.NewTestServer`.
- Toolchain coverage for the `go.mod` `toolchain` directive, `GOTOOLCHAIN`, `GOFIPS140`, `GOEXPERIMENT=nojsonv2`, and Green Tea GC.
- Go 1.27 `gofmt` alignment, `go mod tidy` require-block merging, and the `stdversion` and `printf` vet checks.
- CI matrix coverage for Go 1.26 and Go 1.27.
- A Go release tracking checklist in `CONTRIBUTING.md`.

### Changed

- Expanded the security, concurrency, testing, performance, generics, encoding, HTTP, toolchain, build, database, project-context, observability, error-handling, and pitfalls references.
- Coverage baseline is now Go 1.21 through Go 1.27, reviewed against Go 1.27.4.

### Fixed

- Replaced the stale `version.go` Go version source with the `go.mod` `toolchain` directive and `GOTOOLCHAIN`.
- Removed the stale "when stable" wording for `encoding/json/v2`.

## [1.0.0] - 2026-11-26

Initial release.
