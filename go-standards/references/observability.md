# Observability

Production Go services need three signal types: logs (what happened), metrics (how often / how much), and traces (where time went). This reference covers the community-standard implementation for each.

## Structured logging: log/slog (Go 1.21+)

`log/slog` is the stdlib structured logger. Prefer it over `log.Printf` and third-party loggers for new code.

### Basic usage

```go
import "log/slog"

// Key-value pairs
slog.Info("request received", "method", r.Method, "path", r.URL.Path)
slog.Warn("cache miss", "key", key, "latency_ms", latency.Milliseconds())
slog.Error("query failed", "err", err, "user_id", userID)
```

### Logger with context

Create a named logger and pass it to the functions that need it; do not attach it to the context:

```go
logger := slog.With("service", "payments", "region", "us-east-1")

// Pass the logger through the call chain explicitly
ProcessPayment(ctx, logger, req)
```

Retrieval happens through the function signature. Storing a logger in `context.Value` hides the dependency from callers and removes the type-safe access that a plain parameter provides; see `references/concurrency.md`.

### Log levels and output format

Configure at startup, not at every call site:

```go
h := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    Level: slog.LevelInfo,  // or LevelDebug / LevelWarn / LevelError
})
slog.SetDefault(slog.New(h))
```

Use `slog.NewJSONHandler` in production (machine-readable). Use `slog.NewTextHandler` in local development (human-readable).

### What to log

- **Info**: significant transitions (request start/end, job submitted, config loaded)
- **Warn**: recoverable anomalies (retry, fallback, rate-limit near threshold)
- **Error**: failures that require attention (including `err` as a key, never in the message)
- Never log and return; log at the boundary; propagate errors inward. See `references/error-handling.md`.

### What never to log

Follow the credential, secret, and PII rule in `references/security.md`. In logs specifically, also never emit raw request bodies from untrusted sources.

## Metrics: Prometheus

Use `github.com/prometheus/client_golang` for application metrics.

### Instrument types

| Type      | Use when                                                      |
| --------- | ------------------------------------------------------------- |
| Counter   | Monotonically increasing totals (requests, errors)            |
| Gauge     | Current value that goes up and down (queue depth, goroutines) |
| Histogram | Distribution of values (latency, response size)               |
| Summary   | Pre-computed quantiles (less common; prefer Histogram)        |

### Setup

```go
import (
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promauto"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    requestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
        Name: "http_requests_total",
        Help: "Total HTTP requests.",
    }, []string{"method", "path", "status"})

    requestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
        Name:    "http_request_duration_seconds",
        Help:    "HTTP request latency.",
        Buckets: prometheus.DefBuckets,
    }, []string{"method", "path"})
)

// Expose metrics endpoint
http.Handle("/metrics", promhttp.Handler())
```

### Recording observations

```go
start := time.Now()
// ... handle request ...
requestDuration.WithLabelValues(r.Method, r.URL.Path).
    Observe(time.Since(start).Seconds())
requestsTotal.WithLabelValues(r.Method, r.URL.Path, strconv.Itoa(statusCode)).Inc()
```

**Cardinality warning:** never use unbounded values (user IDs, URLs with query parameters, UUIDs) as label values. High-cardinality labels exhaust Prometheus memory.

## Tracing: OpenTelemetry

Use `go.opentelemetry.io/otel` for distributed tracing. OpenTelemetry is the vendor-neutral standard; it exports to Jaeger, Datadog, Honeycomb, and others.

### Initialise the tracer

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
    "go.opentelemetry.io/otel/sdk/trace"
)

func initTracer(ctx context.Context) (func(), error) {
    exp, err := otlptracehttp.New(ctx)
    if err != nil {
        return nil, fmt.Errorf("create exporter: %w", err)
    }
    tp := trace.NewTracerProvider(trace.WithBatcher(exp))
    otel.SetTracerProvider(tp)
    return func() { tp.Shutdown(ctx) }, nil
}
```

### Instrument code

```go
var tracer = otel.Tracer("payments")

func ProcessPayment(ctx context.Context, req PaymentRequest) error {
    ctx, span := tracer.Start(ctx, "ProcessPayment")
    defer span.End()

    span.SetAttributes(
        attribute.String("payment.method", req.Method),
        attribute.Int64("payment.amount_cents", req.AmountCents),
    )

    if err := charge(ctx, req); err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return err
    }
    return nil
}
```

Always propagate `ctx` through the call tree. Spans are attached to the context and linked automatically.

## Profiling endpoint: pprof

Expose a `pprof` HTTP handler in non-production builds or via an internal-only port. Never expose it to the public internet.

```go
import _ "net/http/pprof"  // blank import registers handlers on http.DefaultServeMux

// In main (on a separate port or behind auth):
go http.ListenAndServe("localhost:6060", nil)
```

Capture profiles:

```bash
go tool pprof http://localhost:6060/debug/pprof/heap
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30
go tool pprof http://localhost:6060/debug/pprof/goroutine
```

See `references/performance.md` for profile interpretation guidance.
