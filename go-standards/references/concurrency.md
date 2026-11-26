# Concurrency

## Core principle

> Do not communicate by sharing memory; share memory by communicating.

Use channels to transfer ownership of data. Use mutexes to protect shared state that multiple goroutines read and write without transferring ownership.

## Execution context: identify before adding concurrency

The correct concurrency approach depends on how the code runs. Identify the context from provided files before making any concurrency decisions:

| Context                       | Default assumption      | Action                                      |
| ----------------------------- | ----------------------- | ------------------------------------------- |
| Web server / HTTP handler     | Concurrent by default   | Fix race conditions without asking          |
| CLI tool / single-run program | Usually not concurrent  | Ask before adding concurrency               |
| Library / package             | Depends on intended use | Ask for clarification                       |
| Uncertain                     | None                    | Ask before making any threading assumptions |

Detection signals: `http.ListenAndServe` or handler registration → web server; `cobra`, `flag`, or `os.Args` parsing in `main` → CLI; no `main` package → library.

## Goroutine lifecycle

Every goroutine must have a defined exit condition. Never launch a goroutine with no way to stop it:

```go
// GOOD: lifecycle controlled by context
func (w *Worker) Run(ctx context.Context) error {
    for {
        select {
        case <-ctx.Done():
            return ctx.Err()
        case job := <-w.jobs:
            if err := w.process(job); err != nil {
                return fmt.Errorf("process job: %w", err)
            }
        }
    }
}

// BAD: goroutine leaks if nothing closes w.jobs
go func() {
    for job := range w.jobs {
        w.process(job)
    }
}()
```

## context.Context

- First parameter of any function that may block, do I/O, or spawn goroutines.
- Never store `Context` in a struct field: pass it explicitly.
- Derive with `WithCancel`, `WithTimeout`, `WithDeadline`; always call the cancel function (defer immediately after creation).

```go
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()
```

### Context Values: narrow, deliberate use only

`context.Value` exists for request-scoped values that must cross an API boundary without every intermediate function needing an explicit parameter for them: a trace ID, a deadline, an authenticated principal passed down through middleware the caller does not control. It is not a general parameter-passing mechanism.

```go
// GOOD: a cross-cutting, request-scoped value with no natural parameter home
type traceIDKey struct{}

func WithTraceID(ctx context.Context, id string) context.Context {
    return context.WithValue(ctx, traceIDKey{}, id)
}

func TraceID(ctx context.Context) (string, bool) {
    id, ok := ctx.Value(traceIDKey{}).(string)
    return id, ok
}
```

```go
// BAD: threading an ordinary dependency through context.Value hides it
// from the function signature and makes the call site impossible to audit
func WithLogger(ctx context.Context, l *slog.Logger) context.Context {
    return context.WithValue(ctx, loggerKey{}, l)
}

func process(ctx context.Context) {
    logger := ctx.Value(loggerKey{}).(*slog.Logger) // hidden dependency, no compile-time check
    ...
}
```

A `*slog.Logger`, a `*Config`, a repository, or any other genuine dependency belongs in a function parameter or a struct field, not in `context.Value`. If it is a required input to the function's logic, hiding it in the context trades a visible, checkable dependency for an invisible one that only fails at runtime, with a type assertion that can panic or silently return the zero value.

Always use an unexported key type, never a bare `string` or `int`, to prevent collisions between unrelated packages that both happen to choose the same key value:

```go
// GOOD: collision-proof; only this package can produce this key type
type traceIDKey struct{}

// BAD: any package using the literal string "traceID" collides with this one
ctx = context.WithValue(ctx, "traceID", id)
```

## Channels

| Pattern         | Use when                                        |
| --------------- | ----------------------------------------------- |
| Unbuffered      | Synchronous handoff; sender waits for receiver  |
| Buffered        | Decouple producer/consumer rate; known capacity |
| `chan struct{}` | Signal shutdown with no data                    |

Close channels on the **sending** side only. Closing signals "no more values": it is not a cleanup mechanism:

```go
func produce(ch chan<- int) {
    defer close(ch)
    for i := 0; i < 10; i++ {
        ch <- i
    }
}
```

## sync primitives

```go
// RWMutex: protect shared state
type Cache struct {
    mu    sync.RWMutex
    items map[string]Item
}

func (c *Cache) Get(key string) (Item, bool) {
    c.mu.RLock()
    defer c.mu.RUnlock()
    item, ok := c.items[key]
    return item, ok
}

// WaitGroup: wait for a fixed set of goroutines
var wg sync.WaitGroup
for _, task := range tasks {
    wg.Add(1)
    go func(t Task) {
        defer wg.Done()
        process(t)
    }(task)
}
wg.Wait()
```

On Go 1.25+, `WaitGroup.Go` combines `Add(1)`, the goroutine, and `Done`:

```go
var wg sync.WaitGroup
for _, task := range tasks {
    wg.Go(func() {
        process(task) // Go 1.22+ loop variable semantics
    })
}
wg.Wait()
```

Use the explicit `Add`/`Done` form when the goroutine is not created at the same point as the `Add`, or when the minimum version is below 1.25.

## errgroup: concurrent tasks with error propagation

Prefer `golang.org/x/sync/errgroup` over raw WaitGroup when goroutines can fail:

```go
g, ctx := errgroup.WithContext(ctx)
for _, url := range urls {
    url := url // required for Go < 1.22
    g.Go(func() error {
        return fetch(ctx, url)
    })
}
if err := g.Wait(); err != nil {
    return fmt.Errorf("fetch urls: %w", err)
}
```

Note: Go 1.22+ fixes loop variable capture: `url := url` not needed.

## Worker pool

Bound concurrency to a deliberate, known worker count, not to `len(jobs)`. An unbounded goroutine-per-item fan-out exhausts memory, file descriptors, or downstream connection pool slots once the input is large enough; a worker pool caps how much work is in flight at once, regardless of how many jobs arrive.

```go
func processAll(ctx context.Context, jobs []Job, workers int) error {
    jobCh := make(chan Job)
    g, ctx := errgroup.WithContext(ctx)

    for i := 0; i < workers; i++ {
        g.Go(func() error {
            for job := range jobCh {
                if err := process(ctx, job); err != nil {
                    return err
                }
            }
            return nil
        })
    }

    g.Go(func() error {
        defer close(jobCh)
        for _, j := range jobs {
            select {
            case jobCh <- j:
            case <-ctx.Done():
                return ctx.Err()
            }
        }
        return nil
    })

    return g.Wait()
}
```

The producer goroutine is itself part of the `errgroup`, and it selects on `ctx.Done()` while sending, so a failure in any worker cancels `ctx`, which then stops the producer from blocking forever on a send that no worker will ever receive. Choose `workers` deliberately: bound it by the actual downstream constraint (available database connections, target CPU utilisation, an upstream rate limit), not by a round number picked without justification.

## select

Non-blocking receive with `default`:

```go
select {
case v := <-ch:
    process(v)
default:
    // ch not ready; continue
}
```

Avoid `time.Sleep` for polling: use `time.Ticker` or `time.After` in a select.

## sync.Once and sync/atomic

```go
// sync.Once: lazy initialisation
var (
    instance *Service
    once     sync.Once
)

func GetService() *Service {
    once.Do(func() { instance = newService() })
    return instance
}
```

Use `sync/atomic` for a single word-sized value updated independently. Use `sync.Mutex` when two or more fields or an invariant must change together.

## Object cleanup (Go 1.24+)

Use `runtime.AddCleanup` instead of `runtime.SetFinalizer` for cleanup tied to object lifetime. `AddCleanup` supports interior pointers, allows multiple cleanups per object, and does not delay collection. Pair it with `weak`. See `references/performance.md` for the weak cache guidance.

See `references/security.md` for zeroing long-lived secrets.

## The Go memory model, briefly

Two goroutines accessing the same variable with no synchronisation between them, no mutex, no channel operation, no atomic operation, have no guaranteed ordering for that access, even when the surrounding code reads as if it executes top to bottom. The compiler and the CPU are both free to reorder unsynchronised memory operations as long as a single goroutine's own observable behaviour is unaffected; nothing in the language guarantees another goroutine sees writes in the order they were issued.

This is why a data race is undefined behaviour in Go, not merely "occasionally reads a slightly stale value." An unsynchronised read racing with a write can, in principle, observe a torn value, a value that was never actually written, or cause the compiler to eliminate a load or store entirely under the assumption that no concurrent modification exists. A `sync.Mutex`, a channel send/receive pair, or a `sync/atomic` operation each establish a happens-before edge; without one, there is no ordering guarantee to reason about at all.

## Race detector

Always run tests with `-race`. The command and the coverage workflow are in `references/testing.md`.
