# Naming Conventions

## General

- `MixedCaps` for everything, never `snake_case` or `SCREAMING_SNAKE`.
- Exported: `MixedCaps`. Unexported: `mixedCaps`.
- Short names in short scopes; descriptive names at package level.
- Avoid redundancy: name things by what they are, not where they live.

## Acronyms

All-caps or all-lowercase, never title-cased:

```go
// GOOD
userID    UserID    parseURL    HTTPClient    ServeHTTP

// BAD
userId    UserId    parseUrl    HttpClient    ServeHttp
```

## Receivers

Short, 1–2 character names derived from the type. Consistent across all methods of a type. Never `self` or `this`:

```go
// GOOD
func (c *Client) Do(req *Request) (*Response, error)
func (c *Client) Close() error

// BAD: inconsistent, or too long
func (client *Client) Do(req *Request) (*Response, error)
func (cl *Client) Close() error
```

## Interfaces

Single-method interfaces: method name plus `-er`:

```go
type Reader interface { Read(p []byte) (n int, err error) }
type Stringer interface { String() string }
type Closer interface { Close() error }
```

Multi-method interfaces: descriptive noun (`Store`, `Handler`, `Registry`).

## Avoid stuttering

Don't repeat the package name in the identifier:

```go
// GOOD (used as http.Handler, bytes.Reader)
package http  →  type Handler interface { ... }
package bytes →  type Reader struct { ... }

// BAD
package http  →  type HTTPHandler interface { ... }
package bytes →  type BytesReader struct { ... }
```

## Constructors

`New` prefix returning a pointer or interface:

```go
func NewClient(cfg Config) *Client
func NewStore(db *sql.DB) Store
```

Single primary type in a package: `New(...)` without the type name.

## Constants and enums

```go
type Direction int

const (
    North Direction = iota
    South
    East
    West
)
```

Avoid untyped `const` blocks for domain values; give them a type.

## Boolean names

Prefix with `is`, `has`, `can`, `should`, or use a positive adjective:

```go
// GOOD
isReady    hasPrefix    canRetry    enabled    valid

// BAD
ready (ambiguous)    notDone (double negative)
```

## Error variables

Exported sentinel errors: `ErrX`. Unexported: `errX`.

```go
var ErrNotFound = errors.New("not found")   // exported
var errTimeout  = errors.New("timeout")     // unexported
```

## Comments and GoDoc

**GoDoc** (doc comments on exported identifiers):

- Must end with a period.
- Must begin with the name of the documented identifier.
- Full sentences; additional sentences allowed.

```go
// Client manages connections to the API server.
type Client struct { ... }

// Do executes the request and returns the server response.
func (c *Client) Do(req *Request) (*Response, error)
```

**Inline comments**:

- Start with a capital letter.
- Omit the trailing period unless the comment is multi-sentence.
- One sentence: `// Retry up to three times before failing`
- Multi-sentence: `// Retry up to three times. Each attempt doubles the backoff.`

Review treatment of existing comments is covered in `references/review.md`.
