# Performance

## Profile before optimising

Never optimise without data. Use `pprof` to identify the actual bottleneck:

```go
import _ "net/http/pprof"  // register handlers on /debug/pprof/
```

For benchmarks and unit profiling:

```bash
go test -bench=. -cpuprofile=cpu.prof -memprofile=mem.prof ./...
go tool pprof cpu.prof
```

State your performance targets (throughput, p95 latency, memory budget) before applying optimisations. Don't change working code to be "faster" without a measured baseline.

## Struct field alignment

Order struct fields from largest to smallest type to minimise padding. The compiler inserts padding to satisfy alignment requirements: wrong ordering wastes memory, especially in large slices of structs.

```go
// BAD: 24 bytes due to padding
type Bad struct {
    a bool    // 1 byte + 7 padding
    b float64 // 8 bytes
    c bool    // 1 byte + 7 padding
}

// GOOD: 16 bytes, no wasted padding
type Good struct {
    b float64 // 8 bytes
    a bool    // 1 byte
    c bool    // 1 byte + 6 padding (one block)
}
```

Use `fieldalignment` from `golang.org/x/tools/go/analysis/passes/fieldalignment` or `golangci-lint` with the `fieldalignment` linter to catch this automatically.

## Slice and map pre-allocation

Always pre-allocate when the size is known or estimable. Growth allocations and copies are the most common source of unnecessary GC pressure.

```go
// BAD: repeated allocations as slice grows
result := []string{}
for _, item := range items {
    result = append(result, transform(item))
}

// GOOD: single allocation
result := make([]string, 0, len(items))
for _, item := range items {
    result = append(result, transform(item))
}

// Map pre-allocation
m := make(map[string]int, len(keys))
```

## sync.Pool for high-frequency allocations

Use `sync.Pool` to reuse objects that are allocated and discarded at high frequency (e.g., buffers, request-scoped objects):

```go
var bufPool = sync.Pool{
    New: func() any { return new(bytes.Buffer) },
}

func process(data []byte) string {
    buf := bufPool.Get().(*bytes.Buffer)
    buf.Reset()
    defer bufPool.Put(buf)

    buf.Write(data)
    return buf.String()
}
```

The GC may reclaim pool objects at any time: do not use `sync.Pool` for objects that must persist.

## String operations

Avoid string concatenation in loops. It allocates a new string each iteration:

```go
// BAD: O(n²) allocations
s := ""
for _, part := range parts {
    s += part
}

// GOOD
var b strings.Builder
b.Grow(estimatedSize)
for _, part := range parts {
    b.WriteString(part)
}
result := b.String()
```

Avoid `fmt.Sprintf` for simple conversions; use `strconv` instead:

```go
// BAD: reflection overhead
s := fmt.Sprintf("%d", n)

// GOOD
s := strconv.Itoa(n)
```

## Escape analysis

Variables that escape to the heap cause allocations. Use `go build -gcflags='-m'` to inspect escape decisions:

```bash
go build -gcflags='-m' ./...
```

Common causes of unintended escapes:

- Storing a pointer in an interface
- Returning a pointer to a local variable
- Closures capturing outer variables
- Passing a local variable to a function that stores it

Prefer value receivers and value types in hot paths to keep objects on the stack.

## GOMAXPROCS in containers

**Go 1.25+**: the runtime now defaults `GOMAXPROCS` to a value that already accounts for the container's cgroup CPU limit (Linux only), and keeps it in sync if that limit changes while the process is running. For a service built with a Go 1.25 or later toolchain, this means no manual configuration is required for the common case, and `go.uber.org/automaxprocs` is redundant: remove it rather than stacking a second mechanism on top of a runtime default that already does the same job.

**Before Go 1.25**, the runtime defaults `GOMAXPROCS` to the number of CPUs on the host machine, not the container's quota. In a container with a CPU limit set lower than the host's core count, this leaves `GOMAXPROCS` far higher than the actual quota, causing excessive scheduler context switching and degraded performance. On a pre-1.25 toolchain, set `GOMAXPROCS` explicitly:

```go
import _ "go.uber.org/automaxprocs"  // reads cgroup CPU quota on init
```

Or set it explicitly in `main`:

```go
runtime.GOMAXPROCS(containerCPULimit)
```

Confirm the actual Go toolchain version in use (`references/project-context.md`) before deciding which of these two paths applies; do not assume 1.25+ behaviour is active just because the code targets a recent language version in `go.mod`, since `go.mod`'s `go` directive sets a language-feature floor, not the exact toolchain used to build the running binary.

## Runtime defaults

Go 1.26 enables the Green Tea garbage collector by default. It improves marking and scanning of small objects and reports a 10 to 40% reduction in GC overhead for GC-heavy programs. It requires no code change. The Go 1.26 opt-out is `GOEXPERIMENT=nogreenteagc`; the opt-out is expected to be removed in a later release.

Go 1.27 adds size-specialized allocation for objects smaller than 80 bytes, with an expected ~1% improvement in allocation-heavy programs and a ~60 KB binary size increase. The opt-out is `GOEXPERIMENT=nosizespecializedmalloc`, expected to be removed in Go 1.28.

Go 1.26 reduces the baseline runtime overhead of cgo calls by about 30%.

Re-measure after a toolchain upgrade. Do not carry `GOGC` or `GOMEMLIMIT` values forward without a benchmark on the new runtime.

## Interning and weak references

Use `unique.Make` (Go 1.23+) to intern immutable values that repeat often, such as strings parsed from a protocol. Equal values share one canonical representation, so two handles compare with `==` without comparing the value.

Use `weak.Make` (Go 1.24+) for caches that must not keep values alive. A weak pointer returns `nil` after the value is collected. Combine it with `runtime.AddCleanup` when the cached value owns a resource that needs explicit release.

```go
type cacheKey struct{ name string }

h := unique.Make(cacheKey{name: "orders"})
v := h.Value()

w := weak.Make(&bigValue)
if p := w.Value(); p != nil {
    use(p)
}
```

## Benchmark discipline

Write benchmarks before and after any performance change to confirm the improvement with data. Always run with `-benchmem` to surface allocation differences:

```bash
go test -bench=BenchmarkX -benchmem -count=5 ./...
```

Use `benchstat` to compare runs statistically:

```bash
go install golang.org/x/perf/cmd/benchstat@latest
benchstat old.txt new.txt
```
