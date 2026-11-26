# HTTP Servers and Clients

Covers `net/http` server routing, middleware, timeouts, graceful shutdown, and client reuse. For HTTP security headers, TLS, and client timeout hardening against SSRF, see `references/security.md`. For the request-scoped context.Value pattern used to carry request metadata through handlers, see `references/concurrency.md`.

## Routing with ServeMux (Go 1.22+)

`net/http.ServeMux` supports method-qualified patterns and wildcards natively; reach for a third-party router only when the application needs something ServeMux genuinely lacks (regex segments, versioned route groups, per-route middleware chains built into the router itself).

```go
mux := http.NewServeMux()

mux.HandleFunc("GET /users", listUsers)
mux.HandleFunc("POST /users", createUser)
mux.HandleFunc("GET /users/{id}", getUser)
mux.HandleFunc("DELETE /users/{id}", deleteUser)

func getUser(w http.ResponseWriter, r *http.Request) {
    id := r.PathValue("id")
    // ...
}
```

### Pattern precedence

When more than one pattern could match a request, ServeMux picks the most specific:

1. An exact segment beats a wildcard segment (`/users/admin` beats `/users/{id}`).
2. A longer pattern beats a shorter one.
3. A method-qualified pattern beats a method-agnostic one for the same path.

```go
mux.HandleFunc("GET /users/admin", handleAdmin)  // wins for GET /users/admin
mux.HandleFunc("GET /users/{id}", handleUser)     // wins for any other GET /users/*
mux.HandleFunc("/users/{id}", handleAnyMethod)    // fallback for non-GET methods
```

A trailing `{$}` restricts a pattern to match only that exact path, not a subtree: `"GET /users/{$}"` matches `/users` but not `/users/5`. Without `{$}`, a pattern ending in `/` still matches everything below it, matching pre-1.22 behavior.

A `{path...}` wildcard captures the remainder of the path, for serving trees such as `http.FileServer`.

## Middleware

The idiomatic signature wraps one `http.Handler` to produce another:

```go
func Logging(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)
        slog.Info("request", "method", r.Method, "path", r.URL.Path, "duration", time.Since(start))
    })
}

handler := Logging(RequireAuth(mux))
```

For three or more layers, or whenever the nesting hides the order of application, use a `chain` helper rather than nesting calls, so the order reads top to bottom:

```go
func chain(h http.Handler, mw ...func(http.Handler) http.Handler) http.Handler {
    for i := len(mw) - 1; i >= 0; i-- {
        h = mw[i](h)
    }
    return h
}

handler := chain(mux, Logging, RequireAuth, RateLimit)
```

Do not write middleware that swallows a panic without re-raising it after cleanup, unless it is specifically a recovery middleware. A recovery middleware belongs at the outermost layer of the chain, so it wraps every handler and every other middleware:

```go
func Recover(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        defer func() {
            if err := recover(); err != nil {
                slog.Error("panic recovered", "err", err, "path", r.URL.Path)
                http.Error(w, "internal server error", http.StatusInternalServerError)
            }
        }()
        next.ServeHTTP(w, r)
    })
}
```

## Server Timeouts

`http.ListenAndServe(addr, handler)` configures no timeouts at all. A client that opens a connection and sends headers one byte at a time can hold that connection, and a worker goroutine, open indefinitely (a Slowloris-style resource exhaustion). Always construct an explicit `http.Server`:

```go
srv := &http.Server{
    Addr:              ":8080",
    Handler:           handler,
    ReadHeaderTimeout: 5 * time.Second,
    ReadTimeout:       10 * time.Second,
    WriteTimeout:      10 * time.Second,
    IdleTimeout:       120 * time.Second,
}
```

`ReadHeaderTimeout` alone closes most of the Slowloris gap and is the one field with no good reason to leave unset. `WriteTimeout` bounds the entire response, including time spent inside the handler; set it generously above the slowest legitimate handler, or omit it and enforce a per-request deadline through `r.Context()` instead when handlers have very different expected durations.

## Graceful Shutdown

```go
func main() {
    srv := &http.Server{Addr: ":8080", Handler: handler}

    go func() {
        if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
            slog.Error("server failed", "err", err)
            os.Exit(1)
        }
    }()

    ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    defer stop()
    <-ctx.Done()

    shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    if err := srv.Shutdown(shutdownCtx); err != nil {
        slog.Error("graceful shutdown failed", "err", err)
    }
}
```

`Shutdown` stops accepting new connections, waits for active handlers to finish, and returns when they do or when the passed context is cancelled, whichever comes first. It never interrupts a handler mid-flight; a handler with no internal timeout can still block shutdown for its full duration, so long-running handlers must themselves respect `r.Context()` cancellation.

## Context Propagation

`r.Context()` is cancelled automatically when the client disconnects or, on the server side, when the ServeMux-registered handler returns. Pass it through to every downstream call, database query, and outbound HTTP request the handler makes, so that work stops when nobody is still waiting for it.

```go
func getUser(w http.ResponseWriter, r *http.Request) {
    user, err := store.GetUser(r.Context(), r.PathValue("id"))
    if err != nil {
        http.Error(w, "not found", http.StatusNotFound)
        return
    }
    json.NewEncoder(w).Encode(user)
}
```

## Reusing http.Client

Never construct a new `http.Client` per request; each one owns its own connection pool, and constructing one per call defeats keep-alive and forces a fresh TCP and TLS handshake every time.

```go
var httpClient = &http.Client{
    Timeout: 10 * time.Second,
    Transport: &http.Transport{
        MaxIdleConns:        100,
        MaxIdleConnsPerHost: 10,
        IdleConnTimeout:     90 * time.Second,
    },
}
```

A single package-level (or dependency-injected) client, shared across the program, is correct. `http.Client` is safe for concurrent use. See `references/security.md` for the client-timeout guidance that complements this (`Timeout` above is the client-side counterpart to the server timeouts set earlier in this file).

## Testing Handlers

```go
func TestGetUser(t *testing.T) {
    req := httptest.NewRequest(http.MethodGet, "/users/42", nil)
    req.SetPathValue("id", "42")
    w := httptest.NewRecorder()

    getUser(w, req)

    if w.Code != http.StatusOK {
        t.Errorf("status = %d, want %d", w.Code, http.StatusOK)
    }
}
```

Use `httptest.NewRecorder` for unit-testing a single handler function directly. Use `httptest.NewServer` when the test needs a real listening address, for example to exercise the full middleware chain or to hand a URL to a client under test.
