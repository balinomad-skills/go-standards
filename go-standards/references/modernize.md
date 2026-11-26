# Modernising Go Code

Apply these patterns when the project's `go.mod` version allows them. Always read `references/project-context.md` first to confirm the version ceiling and whether breaking changes are permitted.

## go fix: automated modernisation

`go fix` (and `gopls`'s `modernize` analyser) can apply many of the patterns below automatically. Run it before a manual review pass:

```bash
go fix ./...          # applies standard fixes
```

Go 1.26 rewrote `go fix` on top of the same analysis framework `go vet` uses, and added a library of "modernizer" fixers covering most of the patterns in this file (range-over-int, `min`/`max`, `slices`/`maps` helpers, and more), plus a `//go:fix inline` directive that lets a package mark a specific function or constant for source-level inlining at every call site the next time `go fix` runs. Go 1.27 added further modernizers: `atomictypes` (replacing manual `sync/atomic` function calls with the `atomic.Int64`-style types), `embedlit` (embedding literal `[]byte` data via `//go:embed` where applicable), `slicesbackward` (using `slices` package equivalents for backward iteration), and `unsafefuncs` (flagging outdated `unsafe` patterns with a safer standard-library equivalent).

With gopls analysis enabled in your editor, the modernize suite flags opportunities as hints. Individual analysers are listed in `golang.org/x/tools/go/analysis/passes/modernize`.

## Go 1.21: builtins and new packages

### min / max builtins

Replace verbose conditional assignments:

```go
// BEFORE
if x > max {
    max = x
}

// AFTER (Go 1.21+)
max = max(max, x)

// Works on any ordered type
smallest := min(a, b, c)
```

### slices package

Replace hand-rolled slice operations with `slices`:

```go
import "slices"

// Sort (replaces sort.Slice)
slices.Sort(nums)
slices.SortFunc(users, func(a, b User) int { return cmp.Compare(a.Name, b.Name) })

// Search
idx, found := slices.BinarySearch(sorted, target)
contains := slices.Contains(s, val)

// Compact, reverse, etc.
slices.Reverse(s)
unique := slices.Compact(s)  // removes adjacent duplicates
```

### maps package

```go
import "maps"

// Clone a map safely
copy := maps.Clone(original)

// Copy all entries from src into dst
maps.Copy(dst, src)

// Collect keys or values
for k := range maps.Keys(m) { ... }  // Go 1.23+ iter
```

### cmp package

```go
import "cmp"

// Three-way comparison
result := cmp.Compare(a, b)  // -1, 0, or 1

// Ordered constraint for generic functions
func Min[T cmp.Ordered](a, b T) T {
    if a < b { return a }
    return b
}
```

### strings.Cut (Go 1.18: often overlooked)

Replace `strings.Index` + manual slicing:

```go
// BEFORE: error-prone index arithmetic
i := strings.Index(s, ":")
if i >= 0 {
    key, val = s[:i], s[i+1:]
}

// AFTER
key, val, found := strings.Cut(s, ":")
```

## Go 1.21: slog

Replace `log.Printf` with structured logging. See `references/observability.md` for full slog patterns.

## Go 1.22: range over integer

Replace C-style counting loops:

```go
// BEFORE
for i := 0; i < n; i++ { ... }

// AFTER (Go 1.22+)
for i := range n { ... }
```

### Loop variable capture fix (Go 1.22)

Before Go 1.22, goroutines in loops required an explicit copy to capture the loop variable. Go 1.22 fixes loop variable semantics: each iteration gets its own variable.

```go
// BEFORE: required explicit capture
for _, u := range urls {
    u := u  // capture copy; remove in 1.22+
    go process(u)
}

// AFTER (Go 1.22+): no copy needed
for _, u := range urls {
    go process(u)
}
```

Remove `u := u` style captures when bumping `go.mod` to 1.22 or later. The `forvar` modernize fixer does this automatically.

## Go 1.22: enhanced ServeMux routing

`net/http.ServeMux` gained method-qualified patterns and path wildcards, closing most of the gap that previously required a third-party router for basic REST-style routing. See `references/http-and-servers.md` for the full pattern, precedence rules, and the `{$}` and `{path...}` wildcard forms.

## Go 1.23: range over function (iterators)

Go 1.23 introduces `iter.Seq` and `iter.Seq2` for pull-style iteration. Functions with signatures `func(yield func(V) bool)` or `func(yield func(K, V) bool)` can be ranged over directly:

```go
import "iter"

func Pairs(m map[string]int) iter.Seq2[string, int] {
    return func(yield func(string, int) bool) {
        for k, v := range m {
            if !yield(k, v) { return }
        }
    }
}

// Consumer
for k, v := range Pairs(m) {
    fmt.Println(k, v)
}
```

Use iterators for custom collection types instead of exposing internal slices.

## Go 1.21: clear builtin

`clear` zeros all elements in a slice or deletes all entries from a map without allocating a new backing store:

```go
// Maps
clear(m)       // deletes all entries; m is non-nil and reusable

// Slices
clear(s)       // zeroes every element; len and cap unchanged
```

Prefer `clear(m)` over `m = make(map[K]V)` when the map will be reused, to avoid a new allocation.

## Go 1.24: b.Loop() in benchmarks

`b.Loop()` is the preferred replacement for `for range b.N` in benchmarks, introduced in Go 1.24. It eliminates common benchmark pitfalls (timer reset, dead-code elimination). See `references/testing.md` for the full pattern.

## Go 1.24: go.mod tool directive

Go 1.24 added a `tool` directive to `go.mod`, letting a module declare build-tool dependencies (linters, code generators) the same way it declares library dependencies, tracked in `go.sum` and installable with `go get -tool` / runnable with `go tool <name>`, without a separate `tools.go` file using a blank import as a workaround.

```go
// go.mod
tool (
    golang.org/x/tools/cmd/stringer
)
```

Replace an existing `tools.go` blank-import file with the `tool` directive when the minimum Go version allows it; the blank-import pattern remains necessary only for a version floor below 1.24.

## Go 1.25: container-aware GOMAXPROCS by default

`GOMAXPROCS` now defaults to a value that accounts for the container's cgroup CPU limit automatically, and updates if that limit changes while the process runs. This removes the need for `go.uber.org/automaxprocs` in most services built with a 1.25+ toolchain. See `references/performance.md` for the full guidance and the version-gating this depends on.

## Go 1.25: testing/synctest

`testing/synctest` (experimental behind `GOEXPERIMENT=synctest` in 1.24, stable in 1.25) provides a fake, controllable clock for testing code built on goroutines, channels, and timers. Go 1.27 adds `synctest.Sleep`, which combines `time.Sleep` and `synctest.Wait`. See `references/testing.md` for the pattern and version gating.

## Go 1.25: WaitGroup.Go

`sync.WaitGroup.Go` adds a task to the group and starts it in one call, removing the `Add`/`Done` boilerplate and the risk of a missing `Done`. See `references/concurrency.md` for the pattern and version gating.

## Go 1.26: new() accepts an expression

The `new` builtin, previously usable only as `new(T)` for a type `T`, now also accepts an expression: `new(expr)` allocates space, stores the expression's value in it, and returns a pointer to it, without a separate variable declaration. This is most useful for building an inline `*T` for an optional field:

```go
// BEFORE: a throwaway variable purely to take its address
discount := computeDiscount(order)
resp.Discount = &discount

// AFTER (Go 1.26+)
resp.Discount = new(computeDiscount(order))
```

See `references/encoding.md` for this pattern applied to an `omitempty` optional-pointer JSON field.

## Go 1.26: experimental goroutine leak profiling

`runtime/pprof` gained an experimental `goroutineleak` profile using reachability analysis to detect goroutines permanently blocked with no path to ever unblock. It stabilised in Go 1.27. See `references/testing.md` for how this complements `goleak`.

## Go 1.26: self-referential type constraints

A generic type may now refer to itself in its type parameter list. See `references/generics-and-reflection.md` for the constraint shape and version gating.

## Go 1.27: generic methods

A method can now declare type parameters of its own, independent of its receiver's, removing a restriction present since generics were introduced in 1.18. See `references/generics-and-reflection.md` for the full pattern and the pre-1.27 workaround (a package-level function instead of a method).

## Go 1.27: generalized function type inference

Type inference for a generic function now applies beyond direct calls: assigning a generic function to a variable of a matching function type, using it in a composite literal, converting it, or sending it on a channel, all infer type arguments the same way a direct call does. See `references/generics-and-reflection.md` for examples.

## Go 1.27: encoding/json/v2 stable

`encoding/json/v2` (and its lower-level `encoding/json/jsontext` streaming companion) graduated from experimental to a stable, supported API. The original `encoding/json` package is unaffected by the Go 1 compatibility promise and remains fully supported; as of 1.27 it is implemented on top of v2 internally, which speeds up unmarshalling for existing v1 callers with no code change required. See `references/encoding.md` for the migration considerations, most notably the nil-slice/nil-map marshalling difference between v1 and v2.

## Go 1.27: promoted fields in struct literals

A struct literal key may name a promoted field from an embedded struct, not only a direct field:

```go
type Object struct {
    Name string
}

type Point3D struct {
    Object
    X, Y, Z float64
}

p := Point3D{Name: "origin", Z: 1}
```

The embedded field itself can still be set as a whole. A key must not name a promoted field when the same literal also sets the embedded struct, and the embedded fields traversed must not be pointers.

## Go 1.27: strings.CutLast and bytes.CutLast

`strings.CutLast` and `bytes.CutLast` return the text before and after the last occurrence of a separator, the mirror of `Cut`:

```go
before, after, found := strings.CutLast(path, "/")
```

## Common modernize checklist

When reviewing or migrating code, check for these opportunities:

| Pattern                                            | Replace with                                     | Min version             |
| -------------------------------------------------- | ------------------------------------------------ | ----------------------- |
| `if a > b { max = a } else { max = b }`            | `max = max(a, b)`                                | 1.21                    |
| `sort.Slice(s, func(i,j int) bool{})`              | `slices.SortFunc(s, cmp.Compare)`                | 1.21                    |
| `strings.Index` + slicing                          | `strings.Cut`                                    | 1.18                    |
| `for i := 0; i < n; i++`                           | `for i := range n`                               | 1.22                    |
| `u := u` inside range loop                         | remove (loop var semantics fixed)                | 1.22                    |
| Third-party router for basic REST routes           | `net/http.ServeMux` method + wildcard patterns   | 1.22                    |
| `for range b.N` in benchmarks                      | `for b.Loop()`                                   | 1.24                    |
| `tools.go` blank-import build tooling              | `go.mod` `tool` directive                        | 1.24                    |
| `log.Printf(...)` for structured logs              | `slog.Info(...)` with key-value pairs            | 1.21                    |
| `m = make(map[K]V)` to clear a map                 | `clear(m)`                                       | 1.21                    |
| `go.uber.org/automaxprocs`                         | runtime default (container-aware)                | 1.25                    |
| Manual `WaitGroup` add/done boilerplate            | `wg.Go(func(){...})`                             | 1.25                    |
| Manual path prefix check                           | `os.Root`                                        | 1.24                    |
| `runtime.SetFinalizer`                             | `runtime.AddCleanup`                             | 1.24                    |
| `map[string]T` used only to deduplicate values     | `unique.Make`                                    | 1.23                    |
| Cache that keeps values alive indefinitely         | `weak.Make` with cleanup                         | 1.24                    |
| Third-party UUID package                           | `uuid.New` / `uuid.Parse`                        | 1.27                    |
| `strings.LastIndex` + slicing                      | `strings.CutLast`                                | 1.27                    |
| Separately declared self-referential constraint    | self-referential type parameter constraint       | 1.26                    |
| Sleep-based test of timers/timeouts                | `testing/synctest`                               | 1.25                    |
| Throwaway variable to take its address             | `new(expr)`                                      | 1.26                    |
| Package-level function instead of a generic method | a method with its own type parameters            | 1.27                    |
| Manual `sync/atomic` function calls                | `atomic.Int64`-style types (`atomictypes` fixer) | 1.19 (fixer added 1.27) |
