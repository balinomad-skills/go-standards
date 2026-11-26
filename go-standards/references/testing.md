# Testing Conventions

## Table-driven tests: the default

Every test with more than one case is table-driven:

```go
func TestAdd(t *testing.T) {
    tests := []struct {
        name string
        a, b int
        want int
    }{
        {"positive numbers", 2, 3, 5},
        {"negative numbers", -1, -2, -3},
        {"both zero", 0, 0, 0},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()
            got := Add(tt.a, tt.b)
            if got != tt.want {
                t.Errorf("Add(%d, %d) = %d; want %d", tt.a, tt.b, got, tt.want)
            }
        })
    }
}
```

**Test case name strings:** short, meaningful, lowercase words separated by spaces. No camelCase, no underscores, no punctuation.

```go
// GOOD
"empty input"
"negative overflow"
"both zero"

// BAD
"TestEmptyInput"
"negative_overflow"
"case1"
```

## Testing non-exported logic

Prefer using exported functions to test non-exported logic where practical. When internal behaviour cannot be reached through the public API, use the same-package test file (`package foo`, not `package foo_test`):

```go
// exported_test.go: package foo_test (black-box, preferred for exported API)
// internal_test.go: package foo (white-box, only when necessary)
```

Do not export symbols solely to make them testable. Redesign the API instead if the internal logic cannot be reached through public surface.

## t.Parallel()

Call `t.Parallel()` at the top of every subtest that does not share mutable state. Call it on the parent test only if its setup is also stateless.

## Assertions

**Stdlib `t.Errorf` / `t.Fatalf`**: preferred for simple comparisons.

**`github.com/stretchr/testify`**: use when deep struct equality or richer diffs are needed. No other external test dependencies unless explicitly approved.

```go
// stdlib
if got != want {
    t.Errorf("got %v; want %v", got, want)
}

// testify where it adds clarity
assert.Equal(t, want, got)
require.NoError(t, err)   // stops test immediately on failure
```

Never mix assertion styles within a single test file.

## Mocking

Small, consumer-defined interfaces (see `references/interfaces.md`) make most test doubles trivial to hand-write, with no mocking framework required:

```go
type fakeUserStore struct {
    getUserFunc func(ctx context.Context, id int) (*User, error)
}

func (f *fakeUserStore) GetUser(ctx context.Context, id int) (*User, error) {
    return f.getUserFunc(ctx, id)
}

func TestHandler_UserNotFound(t *testing.T) {
    store := &fakeUserStore{
        getUserFunc: func(ctx context.Context, id int) (*User, error) {
            return nil, ErrNotFound
        },
    }
    // exercise the handler with store
}
```

A func-field-per-method fake like this needs no code generation and lets each test override only the behaviour it cares about. Reach for a generated mock (`go.uber.org/mock`, the maintained successor to `golang/mock`) once an interface has enough methods that hand-writing a fresh fake per test case becomes repetitive, or when call-count and call-order assertions matter more than return-value stubbing. `testify/mock` is a common alternative with a more assertion-style API.

Never mock a concrete struct type directly. If a test needs to replace a concrete dependency, extract an interface for it first, owned by the consuming package, not the implementing one (see `references/interfaces.md`).

## t.Fatal vs t.Error

- `t.Fatal` / `require.*`: stops the current test immediately. Use when subsequent steps are meaningless if this step fails.
- `t.Error` / `assert.*`: records failure and continues. Use when you want to see all failures in one run.

## Cleanup: even on failure

Use `t.Cleanup` for all teardown. It runs even when the test calls `t.Fatal`:

```go
func TestWithTempFile(t *testing.T) {
    f, err := os.CreateTemp("", "test-*")
    require.NoError(t, err)
    t.Cleanup(func() { os.Remove(f.Name()) })
    // test proceeds: file is removed regardless of outcome
}
```

Never rely on `defer` alone for test cleanup. A single `defer` statement does not guarantee execution after an early return or after `t.Fatal`/`t.FailNow` invoked from a helper function; always register teardown with `t.Cleanup`.

## Test helpers

Mark helpers with `t.Helper()` so failures point to the call site:

```go
func mustParseURL(t *testing.T, raw string) *url.URL {
    t.Helper()
    u, err := url.Parse(raw)
    if err != nil {
        t.Fatalf("parse URL %q: %v", raw, err)
    }
    return u
}
```

## File naming

- Same package (white-box): `foo_test.go` with `package foo`
- External package (black-box): `foo_test.go` with `package foo_test`

Prefer `package foo_test` for exported APIs.

## Benchmarks

```go
func BenchmarkProcess(b *testing.B) {
    data := generateTestData()
    b.ResetTimer()
    for b.Loop() {          // Go 1.24+; use b.N for earlier versions
        Process(data)
    }
}
```

Run with: `go test -bench=. -benchmem ./...`

## Fuzzing

Fuzzing complements table-driven tests; it does not replace them. Reach for it specifically where input is untrusted or unbounded: parsers, deserializers, anything that consumes raw bytes or strings from outside the program. Table-driven tests remain the right tool for everything else, including business logic with a small, known set of cases.

```go
func FuzzParsePort(f *testing.F) {
    f.Add("8080") // seed corpus entries via f.Add
    f.Add("0")
    f.Add("not-a-number")

    f.Fuzz(func(t *testing.T, input string) {
        port, err := parsePort(input)
        if err == nil && (port < 1 || port > 65535) {
            t.Errorf("parsePort(%q) = %d, want error or a valid port", input, port)
        }
    })
}
```

A fuzz target's arguments are limited to `string`, `[]byte`, the integer and float types, and `bool`; a struct is not a valid fuzzing argument. Fuzz targets must be fast, deterministic, and free of dependence on global state, since the fuzzing engine runs them in parallel, in an unpredictable order.

### Running

```bash
go test ./...                                   # runs only the seed corpus, like a normal test
go test -fuzz=FuzzParsePort -fuzztime=30s ./...  # actually fuzzes
```

Without `-fuzz`, a fuzz test runs only its seed corpus, every `f.Add` call plus any files already in `testdata/fuzz/FuzzParsePort/`, as an ordinary test. A fuzz test is therefore always safe to leave in the normal `go test` path; it never blocks a routine run waiting to fuzz.

A failing input is written automatically to `testdata/fuzz/FuzzParsePort/`, becoming a permanent regression case that runs on every future `go test`, fuzzing or not. Commit these files; deleting a discovered-crash file only reintroduces the bug invisibly.

### Fuzzing in CI

Do not gate a normal pull-request pipeline on fuzzing; a fixed, short `-fuzztime` finding nothing proves little, and an open-ended one makes CI duration unpredictable. Run fuzzing on a schedule instead, nightly or as a dedicated long-running job, with any newly-discovered crasher committed to the seed corpus and treated as a build-breaking regression from that point forward.

## Test data

Store fixtures in `testdata/` directories (ignored by the Go build tool). Path is relative to the package directory when run with `go test`:

```go
data, err := os.ReadFile("testdata/input.json")
```

## Cyclomatic complexity

Keep gocyclo complexity of test functions under 15.

## Coverage and race

```bash
go test -race ./...
go test -race -shuffle=on -coverprofile=cov.out ./...
go tool cover -html=cov.out
```

The `-shuffle=on` flag randomises test execution order within each package. This catches tests that pass only because of execution order: a common source of intermittent failures in CI. Always use it in CI alongside `-race`.

100% coverage is not the goal. Cover behaviour, error paths, and edge cases. Missing coverage: summarise conceptually; do not generate tests unless explicitly requested.

## Goroutine leak detection

Use `goleak` to ensure tests do not leave goroutines running after they complete:

```go
import "go.uber.org/goleak"

func TestMain(m *testing.M) {
    goleak.VerifyTestMain(m)
}

// Or per-test:
func TestFoo(t *testing.T) {
    defer goleak.VerifyNone(t)
    // ...
}
```

`goleak` reports leaked goroutines at the end of the test run. It is especially useful for services and workers that use background goroutines.

### Native goroutine leak profiling (Go 1.26+)

Go 1.26 introduced an experimental `goroutineleak` profile in `runtime/pprof`, using reachability analysis to find goroutines permanently blocked on a channel, mutex, or similar primitive; it graduated to a regular, generally-available profile in Go 1.27, and is also exposed through `net/http/pprof` on a running service. This is a different tool for a related job: `goleak` is a `go test`-time assertion, wired into the test binary; the `runtime/pprof` profile is a production-safe diagnostic that can be pulled from a live process with no test-only dependency involved. On Go 1.26 or later, check whether the built-in profile already covers a given leak-detection need, particularly for diagnosing a suspected leak in a running service, before reaching for `goleak` in a package that does not already depend on it.

## Integration tests

Separate integration tests from unit tests using build tags:

```go
//go:build integration

package store_test

import "testing"

func TestDatabaseRoundtrip(t *testing.T) { ... }
```

Run integration tests explicitly:

```bash
go test -tags integration -race -count=1 ./...
```

The `-count=1` flag disables test result caching. Always use it for integration tests that interact with external services: cached results will not re-test a live dependency.

## t.Context (Go 1.24+)

Go 1.24 adds `t.Context()`, which returns a context cancelled when the test completes (including on `t.Fatal`). Prefer it over manual context setup for test helpers:

```go
// Go 1.24+
func TestWithContext(t *testing.T) {
    ctx := t.Context()  // cancelled when test ends
    resp, err := client.Fetch(ctx, url)
    // ...
}
```
