# CI/CD: GitHub Actions for Go

This reference covers writing production-grade GitHub Actions workflows for Go projects. For troubleshooting existing workflow runs, use the `gh` CLI (`gh run view`, `gh run list`, `gh run view --log-failed`).

## Quick reference

| Stage         | Tool / Action                         | Purpose                         |
| ------------- | ------------------------------------- | ------------------------------- |
| Test          | `go test -race -shuffle=on`           | Unit tests + race + order check |
| Lint          | `golangci/golangci-lint-action`       | Comprehensive linting           |
| Vet           | `go vet`                              | Built-in static analysis        |
| Coverage      | `codecov/codecov-action`              | Coverage reporting              |
| Security SAST | `govulncheck`, `gosec`, CodeQL        | Vulnerability detection         |
| go.mod check  | `go mod tidy && git diff --exit-code` | Module hygiene                  |
| Release       | `goreleaser/goreleaser-action`        | Binary builds + GitHub Release  |
| Deps          | Dependabot / Renovate                 | Automated dependency updates    |

Always check the GitHub Marketplace for the latest major version of each action before writing YAML; action versions go stale quickly.

## Workflow structure rules

**Permissions:** Follow least-privilege per job. Set `permissions: read-all` at the top level and grant elevated permissions only where needed.

**Pin action versions** to the latest stable major tag (`@v7`, not `@main` or `@master`). Floating refs allow supply-chain injection.

**fail-fast:** Set `fail-fast: false` on Go version matrices so a failure on one version does not cancel other jobs.

**go mod tidy check:** Always verify `go.mod` and `go.sum` are clean after a `go mod tidy`. A dirty module is a CI signal that a dependency was added without tidying.

```yaml
- name: Verify go.mod is tidy
  run: |
    go mod tidy
    git diff --exit-code go.mod go.sum
```

## Test workflow

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

permissions:
  contents: read

jobs:
  test:
    name: Test (go${{ matrix.go }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        # Adapt to your go.mod minimum version:
        # go 1.23 → ["1.23", "1.24", "stable"]
        # go 1.24 → ["1.24", "stable"]
        go: ["1.23", "1.24", "stable"]

    steps:
      - uses: actions/checkout@v7

      - uses: actions/setup-go@v7
        with:
          go-version: ${{ matrix.go }}
          cache: true

      - name: Verify go.mod is tidy
        run: go mod tidy && git diff --exit-code

      - name: Run tests
        run: go test -race -shuffle=on -coverprofile=coverage.out ./...

      - name: Upload coverage
        uses: codecov/codecov-action@v7
        with:
          files: coverage.out
```

**Key test flags:**

- `-race`: catches data races (undefined behaviour in Go, mandatory)
- `-shuffle=on`: randomises execution order to expose order-dependent tests
- `-coverprofile`: generates coverage data for upload

For integration tests, use `-count=1` (disables caching) and separate them with a build tag:

```bash
go test -tags integration -race -count=1 ./...
```

## Lint workflow

```yaml
# .github/workflows/lint.yml
name: Lint

on: [push, pull_request]

permissions:
  contents: read

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - uses: actions/setup-go@v7
        with:
          go-version: stable
          cache: false # golangci-lint manages its own cache

      - uses: golangci/golangci-lint-action@v9
        with:
          version: latest
```

Configure linters in `.golangci.yml` at the repo root. See `references/toolchain.md` for the recommended linter list.

## Security workflow

```yaml
# .github/workflows/security.yml
name: Security

on:
  push:
    branches: [main]
  pull_request:
  schedule:
    - cron: "0 6 * * 1" # weekly on Monday

permissions:
  contents: read
  security-events: write # CodeQL upload

jobs:
  govulncheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v7
        with:
          go-version: stable
      - run: |
          go install golang.org/x/vuln/cmd/govulncheck@latest
          govulncheck ./...

  codeql:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: github/codeql-action/init@v4
        with:
          languages: go
          queries: security-extended
      - uses: github/codeql-action/autobuild@v4
      - uses: github/codeql-action/analyze@v4
```

`govulncheck` only flags vulnerabilities in code paths your project actually calls, not every CVE in the dependency tree. It is the highest-signal vulnerability tool for Go.

## Dependency updates: Dependabot

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: gomod
    directory: /
    schedule:
      interval: weekly
    groups:
      minor-patch:
        update-types: [minor, patch]
```

Minor/patch updates are grouped into a single PR. Major updates get individual PRs because they may introduce breaking changes.

**Renovate** is the more configurable alternative. It supports automerge natively, runs `go mod tidy` after updates, and handles monorepos. Install the Renovate GitHub App and add `renovate.json` at the repo root.

## Release automation: GoReleaser

GoReleaser automates binary cross-compilation, checksums, and GitHub Releases.

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags: ["v*"]

permissions:
  contents: write # to create GitHub Releases

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0 # GoReleaser needs full history for changelog

      - uses: actions/setup-go@v7
        with:
          go-version: stable

      - uses: goreleaser/goreleaser-action@v7
        with:
          version: latest
          args: release --clean
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

For libraries that don't produce binaries, a simple `gh release create` is often sufficient without GoReleaser.

## Common CI mistakes

| Mistake                             | Fix                                                       |
| ----------------------------------- | --------------------------------------------------------- |
| Missing `-race` in tests            | Always use `go test -race`                                |
| No `-shuffle=on`                    | Randomise order to catch inter-test dependencies          |
| Caching integration test results    | Use `-count=1` to disable caching                         |
| `go mod tidy` not checked           | Add tidy + `git diff --exit-code` step                    |
| `fail-fast: true` on version matrix | One version failing should not cancel other jobs          |
| Floating action refs (`@master`)    | Pin to stable major version (`@v7`)                       |
| No `permissions` block              | Set least-privilege per job; do not rely on repo default  |
| Ignoring `govulncheck` findings     | Fix or suppress with an explicit `//nolint` justification |
