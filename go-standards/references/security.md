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

On Go 1.24+, `crypto/rand.Text` returns a cryptographically secure random string in the RFC 4648 base32 alphabet. It contains at least 128 bits of randomness and is the shortest safe choice when a text token is acceptable:

```go
token := rand.Text()
```

`crypto/rand.Read` is guaranteed not to fail in Go 1.24+; the error is always nil, but keep the error check when the minimum version is lower.

UUIDs are identifiers, not secrets. Use `rand.Text` or `rand.Read` for tokens; do not treat `uuid.New` as a source of unguessable credentials.

## Modern cryptography (Go 1.24+)

Use the standard library before adding a third-party cryptography dependency.

- `crypto/mlkem` (Go 1.24+) implements ML-KEM-768 and ML-KEM-1024, the post-quantum key encapsulation mechanism in FIPS 203. Go 1.24+ enables the X25519MLKEM768 hybrid key exchange in TLS 1.3 by default; no code change is required for TLS clients and servers.
- `crypto/mldsa` (Go 1.27+) implements ML-DSA-44, ML-DSA-65, and ML-DSA-87, the post-quantum signature scheme in FIPS 204. Go 1.27 adds ML-DSA support to `crypto/x509` and TLS 1.3. The package is unavailable with the FIPS 140-3 module v1.0.0; use module v1.26.0 or later.
- `crypto/hpke` (Go 1.26+) implements Hybrid Public Key Encryption (RFC 9180), including post-quantum hybrid KEMs.
- `crypto/hkdf`, `crypto/pbkdf2`, and `crypto/sha3` (Go 1.24+) cover key derivation and SHA-3.

Use ML-KEM when you need key establishment and ML-DSA when you need signatures. Do not compose a new scheme from primitives; use HPKE or TLS when you need a complete protocol.

```go
// Go 1.24+: ML-KEM-768 key encapsulation
dk, err := mlkem.GenerateKey768()
if err != nil {
    return err
}
sharedKey, ciphertext := dk.EncapsulationKey().Encapsulate()
// Send ciphertext to the holder of dk; both sides now share sharedKey.
```

The recipient recovers the same key with `dk.Decapsulate(ciphertext)`. The decapsulation key must remain secret.

## FIPS 140-3 (Go 1.24+)

For regulated deployments, build with the Go Cryptographic Module:

```bash
GOFIPS140=latest go build ./...
```

`GOFIPS140` selects the module version at build time. At runtime, `GODEBUG=fips140=on` enables FIPS 140-3 mode, and `GODEBUG=fips140=only` rejects non-approved algorithms. The `crypto/fips140` package reports the module version and enforcement state.

`fips140=only` is a best-effort testing and debugging mode, not a production setting. It can panic or return errors by design. Most programs should enable FIPS mode with `GOFIPS140` at build time instead.

## Path traversal

Sanitise file paths derived from user input to prevent directory traversal.

On Go 1.24+, use `os.Root` for directory-limited access. It rejects `..` segments and symlinks that resolve outside the root:

```go
root, err := os.OpenRoot(baseDir)
if err != nil {
    return err
}
defer root.Close()

f, err := root.Open(userInput)
if err != nil {
    return fmt.Errorf("open %q: %w", userInput, err)
}
defer f.Close()
```

Before Go 1.24, a prefix check on `filepath.Clean` is the minimum, but it does not stop symlink escapes:

```go
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

- Use `memguard` or `runtime.AddCleanup` for long-lived in-memory secrets when the security model requires it. On Go 1.24+, prefer `AddCleanup`; new code should not use `runtime.SetFinalizer`.

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

## CSRF protection (Go 1.25+)

For browser-facing services, `http.CrossOriginProtection` rejects unsafe cross-origin requests using Fetch metadata. It does not require tokens or cookies:

```go
protection := http.NewCrossOriginProtection()
if err := protection.AddTrustedOrigin("https://app.example.com"); err != nil {
    return err
}
handler = protection.Handler(handler)
```

Wrap the outermost handler so every route is covered. Keep token-based CSRF protection for clients that do not send Fetch metadata, and for state-changing requests from non-browser clients that cannot be distinguished by origin.

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
