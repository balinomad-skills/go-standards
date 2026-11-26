# Toolchain and Package Selection

## Required tooling

These run on every project, non-negotiable:

| Tool                  | Purpose                  | Run                   |
| --------------------- | ------------------------ | --------------------- |
| `gofmt` / `goimports` | Formatting               | On save and in CI     |
| `go vet`              | Correctness checks       | `go vet ./...`        |
| `go test -race`       | Race condition detection | `go test -race ./...` |
| `go mod tidy`         | Keep go.mod/go.sum clean | Before every commit   |

**gofumpt vs gofmt:** `gofumpt` is a stricter superset of `gofmt` that enforces additional blank-line and grouping rules. Prefer `gofumpt` for new projects; it subsumes `gofmt` so they do not conflict. Use `gofmt` as the minimum bar when the project already has a formatter choice locked in.

## Linter: golangci-lint

Use `golangci-lint` with a `.golangci.yml` at the repo root. Recommended linters to enable beyond the defaults:

```yaml
version: "2"
linters:
  enable:
    - bodyclose # HTTP response body not closed
    - errcheck # unchecked errors
    - exhaustive # missing switch cases on enums
    - forbidigo # ban specific function calls (e.g. fmt.Print in prod)
    - gochecknoinits # flag init() usage
    - gocritic # opinionated style checks
    - ineffassign # ineffectual assignments (value never read)
    - nilerr # returning nil alongside a nil error
    - noctx # HTTP requests without context
    - nolintlint # malformed nolint directives
    - prealloc # slice preallocation opportunities
    - revive # drop-in golint replacement
    - sqlclosecheck # sql.Rows/Stmt not closed
    - tparallel # missing t.Parallel() in table tests
    - wrapcheck # unwrapped errors from external packages
  settings:
    govet:
      enable:
        - shadow # variable shadowing (requires explicit enable; slow)
```

Add `gosec` separately for security scanning; see `references/security.md`.

Run: `golangci-lint run ./...`

When adopting linting on a large legacy codebase, split the work across independent categories in parallel to avoid a monolithic fix session:

- Auto-fixable: `golangci-lint run --fix ./...`
- Security linters: `bodyclose`, `sqlclosecheck`, `gosec`
- Error handling: `errcheck`, `nilerr`, `wrapcheck`
- Style/formatting: `gofumpt`, `goimports`, `revive`
- Code quality: `gocritic`, `ineffassign`, `shadow`

## Standard library first

Reach for the stdlib before adding a dependency. Common cases where stdlib is sufficient and an external package is not needed:

- JSON: `encoding/json` (or `encoding/json/v2` when stable in Go 1.27)
- HTTP: `net/http` + `net/http/httptest`
- Logging: `log/slog` (Go 1.21+)
- CLI flags: `flag` for simple tools
- Config: environment variables via `os.Getenv` for 12-factor apps
- Slices: `slices` package (Go 1.21+) for sorting, searching, and comparison
- Maps: `maps` package (Go 1.21+) for cloning, copying, and key listing

## Choosing third-party packages

Use the standard library where it covers the need. When a third-party package is genuinely required, evaluate it at the time of adoption against these criteria:

- **Maintenance**: recent commits, issues acknowledged, no long-abandoned branches. Check the commit graph, not just the star count.
- **License**: permissive and compatible with the project (MIT, Apache 2.0, BSD-3). Copyleft licenses require deliberate review.
- **Dependency footprint**: minimal transitive dependencies. A package that pulls in twenty sub-dependencies carries twenty times the risk.
- **Vulnerability record**: no unpatched CVEs. Run `govulncheck` before adoption and on every dependency update.
- **Community standing**: used by other well-maintained Go projects; documented; tested; ideally vendored in production systems you can inspect.

No specific package recommendations are made in this skill. The right choice varies by project requirements, team familiarity, and the state of the ecosystem at the time. A package that is the obvious choice today may be unmaintained in two years.

## Dependency hygiene

- Vet new dependencies: check license, maintenance status, and CVE history.
- Prefer packages with minimal transitive dependencies.
- Pin indirect dependencies to known-good versions in `go.sum`.
- Run `govulncheck ./...` in CI to catch known vulnerabilities. For the GitHub Actions job that enforces this, see `references/ci.md`.

```bash
go install golang.org/x/vuln/cmd/govulncheck@latest
govulncheck ./...
```
