# Interfaces and Functional Options

## Interface design principles

**Keep interfaces small.** One or two methods is ideal. Large interfaces are hard to implement, hard to mock, and couple consumers to implementations.

```go
// GOOD: single responsibility, easy to satisfy
type Storer interface {
    Store(ctx context.Context, key string, val []byte) error
}

// BAD: forces implementers to provide everything even if caller needs one thing
type Storage interface {
    Store(ctx context.Context, key string, val []byte) error
    Fetch(ctx context.Context, key string) ([]byte, error)
    Delete(ctx context.Context, key string) error
    List(ctx context.Context, prefix string) ([]string, error)
    Ping(ctx context.Context) error
}
```

**Define interfaces at the consumer, not the implementer.** The package that needs the behaviour owns the interface. The package that provides the behaviour exports a concrete type.

```go
// GOOD: handler package defines what it needs
package handler

type UserStore interface {
    GetUser(ctx context.Context, id int) (*User, error)
}

// BAD: store package defines the interface, coupling all consumers to it
package store

type Store interface { ... }
```

**Compose small interfaces into larger ones** when a function genuinely needs multiple behaviours:

```go
type ReadWriter interface {
    io.Reader
    io.Writer
}
```

**Don't abstract preemptively.** Define an interface when you have two or more concrete implementations, or when you need to mock for testing. A single concrete type with no planned variation does not need an interface.

## Composition via Embedding

Struct embedding is Go's mechanism for composing concrete types, the counterpart to interface embedding shown above. An embedded field's methods are promoted to the outer type, so the outer value can call them directly without an explicit accessor:

```go
type Reader struct{ /* ... */ }
func (r *Reader) Read(p []byte) (int, error) { /* ... */ }

type Writer struct{ /* ... */ }
func (w *Writer) Write(p []byte) (int, error) { /* ... */ }

type ReadWriter struct {
    *Reader
    *Writer
}

// rw.Read(...) and rw.Write(...) both work directly, promoted from the
// embedded fields, with no forwarding methods written by hand.
```

This gives composition an ergonomic surface similar to inheritance, a "has-a" relationship that reads almost like "is-a", without an actual subtyping relationship: `ReadWriter` does not satisfy any interface `Reader` implements unless `ReadWriter` itself is asserted against it directly, which it will be, since the promoted method exists on `ReadWriter` too.

Use embedding when the outer type genuinely wants to expose the embedded type's entire method set as part of its own API, most commonly to satisfy an interface (embedding `io.Reader` and `io.Writer` to satisfy `io.ReadWriter`) or to extend a type with additional methods while keeping the original behaviour available unchanged. Prefer a named field over embedding when the outer type should only use the inner type internally, without committing to re-exporting every one of its methods: embedding is not merely a shorter way to write `s.inner.Method()` as `s.Method()`, it is a promise that the inner type's full method set, including anything added to it later, becomes part of the outer type's public API. See `references/pitfalls.md` for the ambiguous-selector failure mode that arises when two embedded types define a method of the same name.

## Compile-time interface verification

Verify that a type satisfies an interface at compile time. Put this near the type definition:

```go
var _ http.Handler = (*MyHandler)(nil)
var _ io.ReadWriter = (*Buffer)(nil)
```

The compiler errors immediately if `MyHandler` no longer satisfies `http.Handler`, rather than at the call site or at runtime.

## Functional options

Use the functional options pattern for constructors that have optional or evolving configuration. It avoids breaking callers when new options are added and produces readable call sites.

```go
type Server struct {
    addr    string
    timeout time.Duration
    logger  *slog.Logger
}

type Option func(*Server)

func WithTimeout(d time.Duration) Option {
    return func(s *Server) { s.timeout = d }
}

func WithLogger(l *slog.Logger) Option {
    return func(s *Server) { s.logger = l }
}

func NewServer(addr string, opts ...Option) *Server {
    s := &Server{
        addr:    addr,
        timeout: 30 * time.Second,       // sensible default
        logger:  slog.Default(),
    }
    for _, opt := range opts {
        opt(s)
    }
    return s
}
```

Call site is self-documenting and adding a new option never breaks existing callers:

```go
s := NewServer(":8080", WithTimeout(10*time.Second), WithLogger(myLogger))
```

**Use functional options when:**

- A constructor has more than 3–4 parameters
- Some parameters are optional with sensible defaults
- You anticipate adding configuration over time
- The API is public and stability matters

**Prefer a config struct when:**

- All fields are required (no defaults needed)
- The configuration is complex enough to benefit from field names at the call site
- The config is passed around, stored, or serialised

```go
// Config struct: good when all fields are required and named clarity helps
type DialConfig struct {
    Host     string
    Port     int
    TLSCert  string
    Timeout  time.Duration
}

conn, err := Dial(DialConfig{Host: "db", Port: 5432, Timeout: 5 * time.Second})
```

## Return interfaces sparingly

Return concrete types from constructors; accept interfaces as parameters. Returning interfaces hides the concrete type, complicates documentation, and forces callers to depend on the interface even when they want the full type.

```go
// GOOD: return concrete type
func NewClient(cfg Config) *Client { ... }

// BAD: caller loses access to concrete methods; documentation obscured
func NewClient(cfg Config) ClientInterface { ... }
```

Exception: when the constructor intentionally hides implementation selection (e.g., a factory that may return one of several concrete types).
