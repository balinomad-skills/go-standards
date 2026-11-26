# JSON and Encoding

Covers `encoding/json` (and, as of Go 1.27, `encoding/json/v2`) struct tags, custom marshaling, streaming, and the common correctness gotchas. For reading struct tags via reflection, see `references/generics-and-reflection.md`.

## encoding/json v1 vs v2 (Go 1.27+)

Go 1.27 promoted `encoding/json/v2` from experimental to a stable API, alongside the lower-level `encoding/json/jsontext` streaming package. The original `encoding/json` package (now informally "v1") is unaffected by the Go 1 compatibility promise and is not going away; as of 1.27 it is internally backed by the v2 implementation, which measurably speeds up unmarshaling while keeping v1's API and behavior unchanged for existing callers.

Decide per project, not per file:

- **New code on Go 1.27+, no existing v1 behavior to preserve**: prefer `encoding/json/v2`. It reports a runtime error for structurally invalid Go types (a malformed tag, for example) instead of silently ignoring the problem, and it is stricter about duplicate keys and case-sensitive field matching, both closer to what most other JSON ecosystems expect.
- **Existing code, or a minimum Go version below 1.27**: stay on `encoding/json` (v1). It remains fully supported indefinitely.

The single behavior difference most likely to bite during a v1-to-v2 migration: v1 marshals a nil slice or nil map as JSON `null`; v2 marshals them as an empty JSON array or object (`[]`, `{}`). Anything downstream that distinguishes `null` from `[]` needs to be checked before migrating a given type.

The examples below use v1 syntax, which remains the more common baseline; each includes a note where v2 differs.

The v2 package adds streaming entry points that do not buffer the whole value: `MarshalWrite`, `MarshalEncode`, `UnmarshalRead`, and `UnmarshalDecode`. All v2 functions accept variadic `Options`, so encode and decode settings are explicit rather than global.

If a Go 1.27 binary needs the v1 implementation for compatibility, build with `GOEXPERIMENT=nojsonv2`. The opt-out is expected to be removed in a later release.

## Struct Tags and omitempty

```go
type Order struct {
    ID       string   `json:"id"`
    Total    float64  `json:"total"`
    Note     string   `json:"note,omitempty"`
    Shipped  bool     `json:"shipped,omitempty"`
    Discount *float64 `json:"discount,omitempty"`
}
```

`omitempty` omits the field when it holds its **zero value**: `0`, `""`, `false`, `nil`, or an empty slice/map/array, not merely "not explicitly set." A `bool` field where `false` is meaningful data, not absence, silently disappears from the output with `omitempty`. Use a pointer (`*bool`) when the distinction between "false" and "not present" matters to a consumer.

`Discount *float64` above is the standard way to make "was this field sent at all" distinguishable from "it was sent as zero." Go 1.26 made this pattern easier to construct: the `new` builtin now accepts an expression, not only a type, so `Discount: new(computeDiscount(order))` builds the pointer inline without a separate variable.

## Custom Marshal and Unmarshal (v1)

Implementing `MarshalJSON` on a type that also needs its default field encoding requires a type-alias trick to avoid infinite recursion, since calling `json.Marshal` on the same named type from inside its own `MarshalJSON` would call itself again:

```go
type User struct {
    ID    int
    Email string
}

func (u User) MarshalJSON() ([]byte, error) {
    type alias User // same fields, no MarshalJSON method
    return json.Marshal(struct {
        alias
        Masked string `json:"masked_email"`
    }{
        alias:  alias(u),
        Masked: maskEmail(u.Email),
    })
}
```

## Streaming

`json.Marshal`/`json.Unmarshal` load the entire value into memory before returning. When the payload may be unbounded, or it is read from or written to a network or file stream, use the streaming forms instead of buffering the whole value:

```go
func decodeOrder(r io.Reader) (*Order, error) {
    var o Order
    if err := json.NewDecoder(r).Decode(&o); err != nil {
        return nil, fmt.Errorf("decode order: %w", err)
    }
    return &o, nil
}
```

`json.NewDecoder(r).Decode(&v)` reads incrementally and does not require the full body to be buffered first; `json.NewEncoder(w).Encode(v)` writes incrementally on the way out. `jsontext.Encoder`/`jsontext.Decoder` in `encoding/json/v2`'s companion package provide the equivalent lower-level, token-based streaming API.

## Unknown and Deferred Fields

```go
dec := json.NewDecoder(r)
dec.DisallowUnknownFields()
if err := dec.Decode(&v); err != nil { ... }
```

`DisallowUnknownFields` turns an unexpected field into a decode error, which is the right default for a strict API contract; without it, a typo'd field name in a client request is silently dropped rather than rejected.

`json.RawMessage` defers parsing of a sub-object until its concrete type is known, common in envelope or event-dispatch formats:

```go
type Event struct {
    Type    string          `json:"type"`
    Payload json.RawMessage `json:"payload"`
}

var e Event
json.Unmarshal(data, &e)
switch e.Type {
case "order_created":
    var p OrderCreated
    json.Unmarshal(e.Payload, &p)
}
```

## Numbers

A JSON number unmarshaled into `any`/`interface{}` becomes a `float64` by default, which silently loses precision for integers larger than 2^53. Use `json.Number` (via `dec.UseNumber()`) to preserve the original textual representation when the target type is not known ahead of time, or decode directly into a typed field (`int64`, not `any`) whenever the schema is known.

## Time

`time.Time` marshals to RFC 3339 by default (`"2026-09-14T10:00:00Z"`), which is almost always the right format for a public API. A different wire format requires a custom `MarshalJSON`/`UnmarshalJSON` pair on a named wrapper type, not a mutation of `time.Time` itself.

## uuid Package (Go 1.27+)

Go 1.27 added a standard-library `uuid` package for generating and parsing UUIDs, removing the need for a third-party dependency (`google/uuid` and similar) in new code that targets 1.27 or later. Existing code on an earlier minimum version, or code already standardized on a third-party UUID package, has no obligation to migrate.
