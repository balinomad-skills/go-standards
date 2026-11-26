# Build and Distribution

Covers build constraints, embedding static assets, cross-compilation, module versioning, and build-time version injection.

## Build Constraints

`//go:build` is the current syntax (the legacy `// +build` comment form is obsolete; `gofmt` rewrites it automatically; do not use it in new code):

```go
//go:build linux && amd64

package main
```

The constraint line must be followed by a blank line before the `package` clause, or the toolchain does not recognize it as a build constraint.

Filename suffixes apply the equivalent constraint without a comment at all: `store_linux.go`, `store_windows.go`, and `store_amd64.go` are included only when building for that GOOS or GOARCH. Prefer the filename form when the entire file is platform-specific; use the `//go:build` comment form when only part of a file's applicability needs to be constrained, or when the condition combines multiple tags.

Build tags are also the standard mechanism for excluding integration tests, fuzz corpora, or experimental code from a normal build:

```go
//go:build integration

package store_test
```

## go:embed

Embed static assets (templates, migrations, default config, a web UI's built output) directly into the binary, so deployment ships one artifact instead of a binary plus a directory of files that can drift out of sync with it:

```go
import "embed"

//go:embed templates/*.html
var templatesFS embed.FS

//go:embed static/version.txt
var versionFile string
```

`embed.FS` implements `fs.FS`, so it composes with `html/template.ParseFS`, `http.FileServerFS` (Go 1.22+), and anything else built on the `io/fs` interfaces without a separate adapter.

## Cross-Compilation

Go cross-compiles without a C toolchain for the target as long as the build does not require cgo:

```bash
GOOS=linux GOARCH=amd64 go build -o app-linux-amd64 .
GOOS=darwin GOARCH=arm64 go build -o app-darwin-arm64 .
GOOS=windows GOARCH=amd64 go build -o app.exe .
```

Set `CGO_ENABLED=0` for a fully static binary, required for a scratch or distroless container base image with no C runtime present:

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o app .
```

If the program (or a dependency) genuinely requires cgo (most commonly a SQLite or a legacy database driver), either cross-compile with a matching C cross-toolchain or build the CI stage on the target platform directly; `CGO_ENABLED=0` silently produces a binary that fails at runtime if a cgo-only code path is actually exercised, so confirm the dependency tree has no such requirement before disabling cgo unconditionally.

## Module Versioning (v2+)

Go's module system encodes a deliberate rule: an incompatible change to a public module is a different import path, not just a different version number. For `v0` and `v1`, the import path is unchanged across releases. Starting at `v2`, both the module path in `go.mod` and every importer's import path must carry the major version suffix:

```text
module github.com/example/mylib/v2
```

```go
import "github.com/example/mylib/v2"
```

This means a `v1` and a `v2` release of the same module can be imported side by side in the same build, as genuinely different packages, which is intentional: it lets a large dependency graph upgrade one module to `v2` without forcing every other dependency to upgrade in lockstep. Bump to `v2` (and beyond) only for an actual breaking API change, not for routine feature additions; semantic versioning within `v1` (`v1.4.0`, `v1.5.0`, ...) covers additive, backward-compatible releases.

## Version Injection at Build Time

Inject a build-time version, commit hash, or build date into a binary via `-ldflags`, rather than hardcoding it or reading it from a file the binary must ship alongside:

```go
package main

var (
    version = "dev"
    commit  = "unknown"
)

func main() {
    fmt.Printf("version %s (%s)\n", version, commit)
}
```

```bash
go build -ldflags "-X main.version=$(git describe --tags) -X main.commit=$(git rev-parse --short HEAD)" .
```

`-X` only works against a package-level `var` of type `string` with no initializer expression more complex than a literal; it cannot set a `const`, and it cannot set a value computed at `init()` time. For a build-info-driven approach that needs no `-ldflags` at all, `runtime/debug.ReadBuildInfo` exposes the module version and VCS revision embedded automatically by `go build` when building from a VCS checkout, at the cost of less control over the exact displayed format.
