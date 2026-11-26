# Error Handling

## Never ignore error returns

Every error return must be handled or explicitly propagated. Never discard with `_` silently. Surface missing error checks and explain their downstream impact during review.

```go
// BAD: silent discard; file may be nil, subsequent reads will panic
f, _ := os.Open(path)

// GOOD
f, err := os.Open(path)
if err != nil {
    return fmt.Errorf("open %s: %w", path, err)
}
```

## Wrapping and context

Always wrap errors with context using `fmt.Errorf` and `%w`:

```go
// GOOD
if err := db.Query(ctx, q); err != nil {
    return fmt.Errorf("fetch user %d: %w", id, err)
}

// BAD: caller cannot unwrap; error loses type information
return fmt.Errorf("fetch user %d: %s", id, err)

// BAD: no context; useless to the caller
return err
```

Error strings are lowercase with no trailing punctuation; they compose: `"open config: read file: unexpected EOF"` not `"Failed to open config!"`.

## Sentinel errors

Define at package level when callers need to distinguish them:

```go
var (
    ErrNotFound   = errors.New("not found")
    ErrPermission = errors.New("permission denied")
)
```

Check with `errors.Is`, not `==`, to support wrapping:

```go
if errors.Is(err, ErrNotFound) { ... }
```

## Custom error types

Use a struct when the error carries data the caller needs to act on:

```go
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation failed on %s: %s", e.Field, e.Message)
}
```

Unwrap with `errors.As`:

```go
var ve *ValidationError
if errors.As(err, &ve) {
    log.Printf("invalid field: %s", ve.Field)
}
```

## Don't log and return

Either log the error or return it, never both. The caller decides what to log:

```go
// BAD
log.Printf("query failed: %v", err)
return fmt.Errorf("query failed: %w", err)

// GOOD: return and let the top-level handler log
return fmt.Errorf("query user: %w", err)
```

## Panic

`panic` is for programmer errors detected at startup or in `main`. Never panic in library code or exported functions.

```go
// OK in main
func main() {
    cfg, err := loadConfig()
    if err != nil {
        log.Fatalf("load config: %v", err)
    }
}

// Never in a library
func (s *Store) Get(id int) (*User, error) {
    // return error, don't panic
}
```

## Error handling in goroutines

Goroutines cannot return errors to their caller. Use `errgroup`:

```go
g, ctx := errgroup.WithContext(ctx)
g.Go(func() error {
    return doWork(ctx)
})
if err := g.Wait(); err != nil {
    return fmt.Errorf("work failed: %w", err)
}
```
