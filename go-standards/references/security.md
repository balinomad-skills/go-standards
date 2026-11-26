# Security

## SQL injection

Never construct SQL queries by string concatenation with user input. Always use parameterised queries:

```go
// BAD: SQL injection vulnerability
query := "SELECT * FROM users WHERE name = '" + name + "'"
rows, err := db.Query(query)

// GOOD: parameterised
rows, err := db.QueryContext(ctx, "SELECT * FROM users WHERE name = $1", name)
```

This applies to all query builders. If using a query builder, verify it produces parameterised queries, not interpolated strings.

## Cryptographic randomness

Use `crypto/rand` for any security-sensitive value: tokens, nonces, salts, session IDs, API keys.

```go
// BAD: predictable, not cryptographically secure
import "math/rand"
token := rand.Int63()

// GOOD
import "crypto/rand"
import "encoding/hex"

func generateToken(n int) (string, error) {
    b := make([]byte, n)
    if _, err := rand.Read(b); err != nil {
        return "", fmt.Errorf("generate token: %w", err)
    }
    return hex.EncodeToString(b), nil
}
```

## Path traversal

Sanitise file paths derived from user input to prevent directory traversal:

```go
// BAD: user could pass "../../etc/passwd"
path := filepath.Join(baseDir, userInput)

// GOOD: verify the resolved path is within the expected root
func safePath(base, name string) (string, error) {
    clean := filepath.Join(base, filepath.Clean("/"+name))
    if !strings.HasPrefix(clean, filepath.Clean(base)+string(os.PathSeparator)) {
        return "", fmt.Errorf("invalid path: %q escapes base directory", name)
    }
    return clean, nil
}
```

## Input validation

Validate all external input (HTTP request bodies, query parameters, headers, environment variables, config files) before use.

Key checks:

- Length limits: reject inputs that exceed expected bounds
- Character set: validate expected format with `regexp` or explicit checks
- Numeric ranges: check min/max before type conversion
- Reject unknown fields in JSON: use `json.Decoder` with `DisallowUnknownFields`

```go
dec := json.NewDecoder(r.Body)
dec.DisallowUnknownFields()
if err := dec.Decode(&input); err != nil {
    http.Error(w, "invalid request", http.StatusBadRequest)
    return
}
```

## Secrets and sensitive data

- Never log tokens, passwords, API keys, or PII. Audit log statements in any code path that handles credentials.
- Never store secrets in source code or `go.mod`-tracked files. Use environment variables or a secrets manager.
- Implement `String() string` on types containing secrets to suppress accidental logging via `%v` or `%s`:

```go
type Credentials struct {
    Username string
    Password string
}

func (c Credentials) String() string {
    return fmt.Sprintf("Credentials{Username: %q, Password: [REDACTED]}", c.Username)
}
```

- Use `memguard` or explicit `runtime.SetFinalizer` zeroing for long-lived in-memory secrets when the security model requires it.

## Integer overflow and conversion

Validate numeric input before narrowing conversions:

```go
// BAD: silent truncation if value > 127
func setLimit(n int64) {
    limit := int8(n)
    apply(limit)
}

// GOOD
func setLimit(n int64) error {
    if n < math.MinInt8 || n > math.MaxInt8 {
        return fmt.Errorf("limit %d out of int8 range", n)
    }
    apply(int8(n))
    return nil
}
```

## HTTP security headers

For HTTP services, set security headers in middleware, not per-handler:

```go
func secureHeaders(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("X-Content-Type-Options", "nosniff")
        w.Header().Set("X-Frame-Options", "DENY")
        w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
        next.ServeHTTP(w, r)
    })
}
```

## HTTP client timeouts

The default `http.Client` has no timeout. An HTTP client without a timeout can hang indefinitely, exhausting goroutines or file descriptors:

```go
// BAD
resp, err := http.Get(url)

// GOOD
client := &http.Client{Timeout: 10 * time.Second}
resp, err := client.Get(url)
```

## gosec linter

Add `gosec` to the golangci-lint configuration to catch security issues automatically:

```yaml
linters:
  enable:
    - gosec
```

Key rules it enforces: hardcoded credentials (G101), SQL injection (G202), file path traversal (G304), weak crypto (G401/G501), `math/rand` for security (G404), missing TLS verification (G402).
