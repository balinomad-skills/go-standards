# Common Pitfalls

Patterns that are syntactically valid Go but behaviourally wrong. Flag these during review; never introduce them in new code.

## Nil interface trap

A typed nil is not a nil interface. An interface value is nil only when both its type and value are nil. This is the most counterintuitive bug in Go.

```go
type MyError struct{ msg string }
func (e *MyError) Error() string { return e.msg }

func getError() error {
    var err *MyError = nil
    return err  // NOT nil: interface has type *MyError, value nil
}

// Caller is surprised:
if getError() != nil {
    // This branch is taken, even though err was nil
}
```

**Fix:** Return `nil` directly, not a typed nil pointer:

```go
func getError() error {
    return nil  // truly nil interface
}
```

## Variable shadowing with :=

`:=` inside an inner block creates a new variable, silently shadowing the outer one. The outer variable is never updated.

```go
// BAD: err inside the if block shadows outer err; outer err unchanged
err := doFirst()
if err == nil {
    result, err := doSecond()  // new err, shadows outer
    _ = result
}
// outer err is still the result of doFirst()

// GOOD
var result Result
err := doFirst()
if err == nil {
    result, err = doSecond()  // assigns to outer err
}
```

Run `go vet ./...` and enable the `shadow` linter to catch this.

## Copying a sync.Mutex or sync.WaitGroup

`sync.Mutex`, `sync.WaitGroup`, and other `sync` primitives must not be copied after first use. Copying duplicates the internal state and produces two independent (broken) locks.

```go
// BAD: copies the mutex
type Cache struct{ mu sync.Mutex }
func process(c Cache) { c.mu.Lock() ... }  // c is a copy

// GOOD: use a pointer receiver, or pass a pointer
func process(c *Cache) { c.mu.Lock() ... }
```

`go vet` catches this with the `copylocks` analyser.

## defer in a loop

`defer` statements in a loop don't execute at the end of each iteration: they execute when the enclosing function returns. This causes resource leaks in long-running loops.

```go
// BAD: all file handles stay open until the function returns
for _, path := range paths {
    f, err := os.Open(path)
    if err != nil { ... }
    defer f.Close()  // wrong: deferred until function exit
    process(f)
}

// GOOD: extract to a function so defer runs at the right time
for _, path := range paths {
    if err := processFile(path); err != nil { ... }
}

func processFile(path string) error {
    f, err := os.Open(path)
    if err != nil { return err }
    defer f.Close()  // runs when processFile returns
    return process(f)
}
```

## defer argument evaluation timing

A deferred call's arguments are evaluated when the `defer` statement executes, not when the deferred call actually runs. Only the call itself is postponed; the argument expressions are not.

```go
// BAD: captures x's value (1) at the defer statement, not at function exit
func process() {
    x := 1
    defer fmt.Println("x was", x)
    x = 2
    // prints "x was 1"
}

// GOOD: a closure defers evaluation of x along with the call
func process() {
    x := 1
    defer func() { fmt.Println("x was", x) }()
    x = 2
    // prints "x was 2"
}
```

This is the same rule that makes `defer mu.Unlock()` safe regardless of what `mu` is reassigned to later: `mu` itself, a fixed reference, is captured at the `defer` line, and there is no expression evaluation left to postpone. It becomes a bug specifically when the deferred call's arguments are computed from values that change before the function returns, as in the example above, or when a named return value is read by a plain (non-closure) deferred call instead of being modified by the closure form used to adjust a named return after the fact.

## Append aliasing

Two slices sharing a backing array will corrupt each other on append if capacity allows the write without growing.

```go
a := make([]int, 3, 5)  // len=3, cap=5
b := a[:2]              // shares backing array

b = append(b, 99)       // writes into a's backing array at index 2
// a[2] is now 99, silently
```

**Fix:** Use `a[low:high:max]` (three-index slice) to limit capacity and force a copy on append:

```go
b := a[:2:2]  // cap=2; append will allocate a new backing array
```

## Map iteration order

Map iteration order in Go is intentionally randomised on each run. Never write code that depends on map key order.

```go
// BAD: output is non-deterministic
for k, v := range m {
    fmt.Println(k, v)
}

// GOOD: collect keys, sort, then iterate
keys := make([]string, 0, len(m))
for k := range m {
    keys = append(keys, k)
}
sort.Strings(keys)
for _, k := range keys {
    fmt.Println(k, m[k])
}
```

## time.Time comparison

`time.Time` values include a monotonic clock reading and a location. The `==` operator compares all fields including location, which can produce unexpected inequality for times that represent the same instant.

```go
// BAD: may be false even for the same instant in different locations
if t1 == t2 { ... }

// GOOD
if t1.Equal(t2) { ... }       // compares instants, ignores location
if !t1.Before(t2) { ... }     // for ordering
```

This is also why `comparable` is a misleading constraint name for generic code involving `time.Time`, see `references/generics-and-reflection.md`: `comparable` guarantees `==` compiles, not that the result is the comparison you actually want.

## Goroutine leak from abandoned channel

A goroutine blocked on a channel send or receive with no reader/writer will leak permanently. Always ensure goroutines have an exit path.

```go
// BAD: if caller returns early, goroutine blocks forever on ch <- result
func run() chan int {
    ch := make(chan int)
    go func() { ch <- expensiveWork() }()
    return ch
}

// GOOD: use a context for cancellation or a buffered channel
func run(ctx context.Context) chan int {
    ch := make(chan int, 1)  // buffered: sender never blocks
    go func() {
        select {
        case ch <- expensiveWork():
        case <-ctx.Done():
        }
    }()
    return ch
}
```

See `references/testing.md` for both `goleak` and the native `runtime/pprof` `goroutineleak` profile (experimental behind `GOEXPERIMENT` in Go 1.26, generally available in Go 1.27) that catch this class of bug.

## Integer overflow in type conversions

Converting between integer types silently truncates values that don't fit.

```go
var big int64 = 300
small := int8(big)  // small == 44, silently truncated
```

Always validate ranges before narrowing conversions in production code, especially when the source is external input.

## Nil map write panics

Reading from a nil map is safe (returns the zero value). Writing to a nil map panics at runtime.

```go
// GOOD: always initialise maps before writing
users := map[string]int{}          // empty, not nil
counts := make(map[string]int)     // same

// BAD: panics on the first write
var counts map[string]int
counts["alice"]++  // panic: assignment to entry in nil map
```

Preallocate when the approximate size is known:

```go
m := make(map[string]int, len(items))  // avoids repeated rehashing
```

## Nil slice vs empty slice: JSON serialization

A nil slice marshals to `null` in JSON. An empty (non-nil) slice marshals to `[]`. For API responses this distinction matters, and the exact rule differs between `encoding/json` and `encoding/json/v2` as of Go 1.27, see `references/encoding.md`.

```go
var nilSlice []string    // marshals → null
emptySlice := []string{} // marshals → []

json.Marshal(nilSlice)    // []byte("null")
json.Marshal(emptySlice)  // []byte("[]")
```

**Rule:** initialise slices that will be returned to callers, especially in API response types. Use `var s []T` only when `nil` is a meaningful sentinel (e.g., "field was not set").

```go
type Response struct {
    Items []string `json:"items"`
}

// BAD: Items marshals to null if no items
func handler() Response { return Response{} }

// GOOD: Items marshals to []
func handler() Response { return Response{Items: []string{}} }
```

## Composite literal positional fields

Composite literals without field names are fragile: adding or reordering struct fields breaks callers silently or causes a compile error only if the count changes.

```go
type Point struct{ X, Y, Z int }

// BAD: positional; breaks if fields are reordered or a new one is added
p := Point{1, 2, 3}

// GOOD: explicit field names; survives struct evolution
p := Point{X: 1, Y: 2, Z: 3}
```

The only exception is small, stable standard library types where positional literals are idiomatic (e.g., `image.Point{10, 20}`).

## Struct embedding: ambiguous selectors and shadowing

Embedding is composition, not inheritance. The outer type does not "override" an embedded type's method in the way a subclass overrides a parent's; it merely defines its own method of the same name at a shallower depth, which Go's selector resolution prefers.

```go
type Base struct{}
func (Base) Name() string { return "base" }

type Wrapper struct {
    Base
}
func (Wrapper) Name() string { return "wrapper" } // shadows Base.Name at depth 0

w := Wrapper{}
w.Name()      // "wrapper" (the shallower method wins)
w.Base.Name() // "base" (still reachable explicitly through the field)
```

If a struct embeds two types that both define a method of the same name at the same depth, the selector is genuinely ambiguous and the code does not compile until one is promoted explicitly or the call is qualified:

```go
type A struct{}
func (A) Describe() string { return "a" }

type B struct{}
func (B) Describe() string { return "b" }

type Combined struct {
    A
    B
}

c := Combined{}
c.Describe() // compile error: ambiguous selector c.Describe
c.A.Describe() // fine: explicit
```

Embedding also silently promotes every exported method the embedded type has today, and every exported method added to it in the future, into the outer type's method set. Treat embedding as an API commitment, not a convenience shortcut, especially when embedding a type from another package: a later addition to that type's method set becomes part of the outer type's public API without any change to the outer type's own source. See `references/interfaces.md` for when embedding is, and is not, the right composition tool.

## init() abuse

`init()` functions run before `main`, in import order, and cannot be tested directly or return errors. They are appropriate only for:

- Registering codecs, drivers, or plugins (e.g., `database/sql` drivers)
- Initialising truly static, infallible state

Never use `init()` to:

- Open files, network connections, or databases
- Perform logic that can fail
- Set global state that varies between test and production
