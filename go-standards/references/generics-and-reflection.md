# Generics and Reflection

Generics (type parameters, Go 1.18+) and reflection (the `reflect` package) both let code operate across types. Prefer generics: they are checked at compile time and carry no per-call dispatch cost for most instantiations. Reach for reflection only when the set of types is not known until runtime, or when working with struct tags.

## When to Use Generics

Use a type parameter when:

- The same logic must run over multiple types with no runtime type-switching.
- A data structure (queue, stack, tree, cache) must hold one caller-chosen type safely, without `any` and type assertions.

Do not use a type parameter when:

- A single method on an interface already expresses the abstraction, see `references/interfaces.md`.
- Only one concrete type is ever passed in practice. Generics without multiple call sites are complexity with no payoff.

## Type Parameters and Constraints

```go
func Max[T cmp.Ordered](a, b T) T {
    if a > b {
        return a
    }
    return b
}
```

`constraints.Ordered` moved into the standard library as `cmp.Ordered` (`cmp` package, Go 1.21+). Avoid the `golang.org/x/exp/constraints` import for new code.

### Built-in constraints

| Constraint    | Permits                                 |
| ------------- | --------------------------------------- |
| `any`         | Every type, equivalent to `interface{}` |
| `comparable`  | Types supporting `==` and `!=`          |
| `cmp.Ordered` | Types supporting `<`, `<=`, `>`, `>=`   |

### Custom constraints

```go
type Number interface {
    ~int | ~int32 | ~int64 | ~float32 | ~float64
}

func Sum[T Number](values []T) T {
    var total T
    for _, v := range values {
        total += v
    }
    return total
}
```

The `~` before a type means "this type, and any type whose underlying type is this type." It lets the constraint match named types such as `type Celsius float64`, not only the predeclared type itself.

## Generic Types

```go
type Stack[T any] struct {
    items []T
}

func NewStack[T any]() *Stack[T] {
    return &Stack[T]{}
}

func (s *Stack[T]) Push(v T) {
    s.items = append(s.items, v)
}

func (s *Stack[T]) Pop() (T, bool) {
    var zero T
    if len(s.items) == 0 {
        return zero, false
    }
    v := s.items[len(s.items)-1]
    s.items = s.items[:len(s.items)-1]
    return v, true
}
```

Every generic type needs an explicit zero value (`var zero T`) for a "not found" return path. `nil` does not compile for a bare type parameter unless the constraint guarantees a pointer, slice, map, channel, function, or interface type.

## Generic Methods (Go 1.27+)

Before Go 1.27, a method could use its receiver's type parameters but could not declare new ones of its own; any function needing its own type parameter had to be a package-level function. Go 1.27 lifted this restriction: a method may now declare type parameters that are independent of its receiver's.

```go
// Go 1.27+: the method introduces its own type parameter U, separate
// from the receiver's T.
func (s *Stack[T]) MapTo[U any](fn func(T) U) *Stack[U] {
    out := NewStack[U]()
    for _, v := range s.items {
        out.Push(fn(v))
    }
    return out
}
```

If the declared minimum Go version (see `references/project-context.md`) is below 1.27, keep the older pattern: a standalone function taking the receiver's value as a plain argument.

```go
// Pre-1.27 equivalent: a package-level function, not a method
func ConvertStack[T, U any](s *Stack[T], fn func(T) U) *Stack[U] { ... }
```

Interface methods still cannot declare their own type parameters, and a generic method cannot implement an interface method. This limitation is unchanged in 1.27.

## Type Inference Limits

Go infers type arguments from function arguments, not from return values or surrounding context alone.

```go
// Inferred from the call: T = int
result := Max(3, 5)

// Cannot infer from an empty literal, instantiate explicitly
s := NewStack[string]()
```

Function type inference was generalized in Go 1.27 to also apply when a generic function is assigned to a variable of a matching function type, used in a composite literal, converted, or sent on a channel, not only when it is called directly.

```go
type IntFormatter func(int) string

func GenericFormatter[T any](v T) string { return fmt.Sprintf("value: %v", v) }

// Go 1.27+: T = int is inferred in all three of these contexts
formatters := []IntFormatter{GenericFormatter}
fn := IntFormatter(GenericFormatter)
ch := make(chan IntFormatter, 1)
ch <- GenericFormatter
```

## Common Generics Mistakes

**`comparable` means "supports `==`," not "supports a useful equality check."** Two struct values are `comparable` if every field is, but the comparison is a memberwise `==`, not a semantic check. A struct embedding a `time.Time` with a monotonic reading compares incorrectly (see `references/pitfalls.md`).

**A generic function's performance characteristics depend on the constraint and compiler version.** Go's implementation may use a shared dictionary-based approach or per-type instantiation depending on the constraint. Benchmark before assuming generics remove interface-dispatch overhead, see `references/performance.md`.

**Generic type aliases** (`type Pair[T any] = pair[T]`) require Go 1.24+. Do not use them if the declared minimum version is lower.

## Reflection

Use `reflect` only when the concrete type is not known at compile time and generics cannot express the requirement. The two common legitimate cases are struct-tag-driven libraries (encoding, validation, ORMs) and genuinely dynamic dispatch (plugin systems, RPC frameworks).

```go
func FieldNames(v any) []string {
    t := reflect.TypeOf(v)
    if t.Kind() == reflect.Pointer {
        t = t.Elem()
    }
    names := make([]string, 0, t.NumField())
    for i := 0; i < t.NumField(); i++ {
        names = append(names, t.Field(i).Name)
    }
    return names
}
```

### Reflection costs

Reflection allocates, bypasses inlining, and defeats most compiler optimizations. A reflection-heavy hot path is commonly 10 to 50 times slower than the equivalent direct code. Cache `reflect.Type` and `reflect.Value` lookups outside the hot loop when reflection cannot be avoided, and profile before accepting the cost (`references/performance.md`).

### Struct tag reading

```go
type User struct {
    Name string `validate:"required"`
    Age  int    `validate:"min=0,max=150"`
}

t := reflect.TypeOf(User{})
for i := 0; i < t.NumField(); i++ {
    tag := t.Field(i).Tag.Get("validate")
    // parse tag
}
```

Reading tags is cheap relative to invoking methods via reflection (`reflect.Value.Call`). Prefer designs that read tags once, at startup, to build a cached execution plan, over designs that reflect on every request.

### Reflection vs generics decision table

| Need                                                         | Use                                                            |
| ------------------------------------------------------------ | -------------------------------------------------------------- |
| Same algorithm, several known types, checked at compile time | Generics                                                       |
| Struct-tag-driven behavior: JSON, validation, ORM mapping    | Reflection, see `references/encoding.md`                       |
| Truly unknown types at compile time: plugins, RPC            | Reflection, or `any` with a type switch for a small closed set |
| A single interface method already captures the behavior      | Neither. Use an interface (`references/interfaces.md`)         |

`unsafe` is out of scope for this skill except for one note: it is never a substitute for reflection or generics in application code. Its only legitimate application-level use is at the cgo boundary or inside container and serialization libraries implemented at the standard-library level. Treat any `unsafe` import outside that context as a design smell requiring explicit justification.
