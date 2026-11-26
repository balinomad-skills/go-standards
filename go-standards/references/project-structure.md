# Project Structure

## Module layout

```text
myproject/
├── go.mod
├── go.sum
├── cmd/
│   ├── server/
│   │   └── main.go
│   └── migrate/
│       └── main.go
├── internal/
│   ├── store/
│   │   ├── store.go
│   │   └── store_test.go
│   └── handler/
│       ├── handler.go
│       └── handler_test.go
├── config/
│   └── config.go
└── README.md
```

## Rules

**`cmd/`**: one subdirectory per binary, each with a `main.go`. Keep `main` thin: parse flags, wire dependencies, call into `internal/`.

**`internal/`**: the default home for all application packages. The compiler enforces that nothing outside the module can import `internal/`. Prefer this over `pkg/`.

**`pkg/`**: only if you are intentionally publishing packages for external use. Most projects don't need it.

**Flat is fine**: a project with one package and no separate binaries does not need `cmd/` or `internal/`. A single package at the root is idiomatic for such tools and libraries.

**One package per directory.** No exceptions. Mixed packages in a directory (other than `_test` files) are a build error.

## Package design

- Name packages by what they provide, not what they contain: `store` not `storage`, `auth` not `authutils`.
- Avoid `util`, `common`, `helpers`, `misc`; these are grab-bags, not packages. If you need one, it means the thing hasn't found its home yet.
- Package names are lowercase, single words, no underscores.
- Circular imports are a compile error; if two packages need each other, extract the shared interface into a third package.

## Interface placement

Define interfaces where they are used, not where the implementation lives. For interface design patterns, composition rules, compile-time verification, and functional options, see `references/interfaces.md`.

## Dependency injection

Wire dependencies explicitly through constructors. Avoid `init()` and global state for anything that could fail or vary between tests and production:

```go
// GOOD
func NewServer(db *sql.DB, cfg Config, logger *slog.Logger) *Server

// BAD: hidden global dependencies
var db *sql.DB
func init() { db = mustConnect() }
```

## go.mod

- Module path: `github.com/<org>/<repo>` or your canonical domain.
- Minimum version of Go: set the lowest version that still satisfies the required language features, ideally the current stable release.
- Run `go mod tidy` before committing; fail CI if `go.mod` or `go.sum` are dirty.
