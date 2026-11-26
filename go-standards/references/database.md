# Database Access

Covers the Go-side API for talking to a relational database: connection pooling, context propagation, transactions, and scanning. This file does not cover SQL query design, schema design, or query performance tuning; those are out of scope here. See `references/security.md` for SQL-injection prevention (parameterized queries).

## Connection Pool Configuration

`*sql.DB` is not a single connection; it is a pool, safe for concurrent use across goroutines. Set `SetMaxOpenConns`, `SetMaxIdleConns`, and `SetConnMaxLifetime` explicitly for any service that handles concurrent requests:

```go
db, err := sql.Open("pgx", dsn)
if err != nil {
    return fmt.Errorf("open db: %w", err)
}

db.SetMaxOpenConns(25)
db.SetMaxIdleConns(25)
db.SetConnMaxLifetime(30 * time.Minute)
db.SetConnMaxIdleTime(5 * time.Minute)
```

| Setting              | Default   | Effect                                                                                                                                                                          |
| -------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SetMaxOpenConns`    | unlimited | Caps total connections. Past this, callers block waiting for one to free up, so an undersized limit can deadlock a program that needs two connections at once to make progress. |
| `SetMaxIdleConns`    | 2         | Raising this avoids reconnect churn under bursty parallel load; it has no effect above `MaxOpenConns`.                                                                          |
| `SetConnMaxLifetime` | unlimited | Forces periodic reconnection, useful for rotating through a load balancer or avoiding a database-side idle-connection reap.                                                     |
| `SetConnMaxIdleTime` | unlimited | Closes idle connections after the given duration, releasing them once a burst has passed.                                                                                       |

Set `MaxIdleConns` equal to `MaxOpenConns` in most services; a pool that constantly opens and closes connections because idle capacity is too low gains nothing from the higher open-connection ceiling.

## Context-Aware Queries

Always use the `Context` variant (`QueryContext`, `ExecContext`, `PrepareContext`, `QueryRowContext`), never the bare `Query`/`Exec`, in any code path that has a request-scoped or otherwise cancellable context available. The bare methods are `...Context(context.Background(), ...)` in disguise: a slow query outlives a client that has already disconnected, holding a pool connection and database-side resources for no one.

```go
func (s *Store) GetUser(ctx context.Context, id int) (*User, error) {
    var u User
    err := s.db.QueryRowContext(ctx, `SELECT id, name FROM users WHERE id = $1`, id).
        Scan(&u.ID, &u.Name)
    if errors.Is(err, sql.ErrNoRows) {
        return nil, ErrUserNotFound
    }
    if err != nil {
        return nil, fmt.Errorf("query user %d: %w", id, err)
    }
    return &u, nil
}
```

## Transactions

Begin, defer a rollback unconditionally, then commit last. `Rollback` after a successful `Commit` returns `sql.ErrTxDone`, which is safe to ignore; the defer pattern below relies on that.

```go
func (s *Store) Transfer(ctx context.Context, from, to int, amount int64) error {
    tx, err := s.db.BeginTx(ctx, nil)
    if err != nil {
        return fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback() //nolint:errcheck // no-op if Commit already succeeded

    if _, err := tx.ExecContext(ctx, `UPDATE accounts SET balance = balance - $1 WHERE id = $2`, amount, from); err != nil {
        return fmt.Errorf("debit account %d: %w", from, err)
    }
    if _, err := tx.ExecContext(ctx, `UPDATE accounts SET balance = balance + $1 WHERE id = $2`, amount, to); err != nil {
        return fmt.Errorf("credit account %d: %w", to, err)
    }

    if err := tx.Commit(); err != nil {
        return fmt.Errorf("commit transfer: %w", err)
    }
    return nil
}
```

Never share a `*sql.Tx` across goroutines. Unlike `*sql.DB`, a transaction is not safe for concurrent use.

## NULL Handling

A `SELECT` column that can be `NULL` needs a nullable-aware destination, or the scan fails at runtime with `converting NULL to <type> is unsupported`.

```go
var name sql.NullString
if err := row.Scan(&name); err != nil { ... }
if name.Valid {
    fmt.Println(name.String)
}
```

Prefer a pointer type (`*string`, `*int64`) over `sql.NullString`/`sql.NullInt64` in application structs passed beyond the data-access layer; a `*string` is `nil`-checkable with plain Go idiom and does not leak a database-package type into unrelated code. Reserve the `sql.NullX` types for the narrow scope of the `Scan` call itself when a driver or scanning library does not offer a more convenient option.

## Avoiding N+1 Query Loops

Issuing one query per row of an earlier result set is the most common Go-side database performance defect, and it is a Go loop-structure problem as much as a SQL one:

```go
// Wrong: one query per user, N+1 round trips
users, _ := listUsers(ctx)
for _, u := range users {
    orders[u.ID], _ = getOrdersForUser(ctx, u.ID) // N additional queries
}

// Correct: one batched query with an IN list, or a JOIN
ids := make([]int, len(users))
for i, u := range users {
    ids[i] = u.ID
}
orders, _ := getOrdersForUsers(ctx, ids) // one query, map keyed by user ID
```

## sqlx and sqlc

`database/sql` alone requires manual `Scan` calls, one destination per column. Two common upgrades:

- **`jmoiron/sqlx`**: adds `StructScan`/`Get`/`Select` to map rows onto struct fields by `db` tag, with no code generation. Reach for it when hand-written `Scan` calls have become repetitive boilerplate.
- **`sqlc`**: generates fully-typed Go functions from `.sql` files at build time, so a query and its Go signature cannot drift apart; a broken query fails at generation time, not at runtime. Reach for it when compile-time verification of every query matters more than writing queries inline in Go source.

Neither is required for `database/sql` to be idiomatic; both are common, well-supported choices when the manual-`Scan` ceremony is the actual pain point.

## Migrations

Schema migrations are not part of `database/sql`. Pick one tool and commit to its convention (up/down files, a single `schema.sql`, or a declarative diff) rather than hand-rolling `ALTER TABLE` execution in application startup code:

| Tool                     | Style                                                             |
| ------------------------ | ----------------------------------------------------------------- |
| `golang-migrate/migrate` | Versioned up/down SQL files, driven from the CLI or as a library  |
| `pressly/goose`          | Versioned SQL or Go migration files, similar model to `migrate`   |
| `ariga/atlas`            | Declarative: describe the desired schema, atlas computes the diff |

Never run migrations automatically on every service startup in a multi-replica deployment; a rolling deploy can run the same migration from several replicas concurrently. Run migrations as a separate, single-instance step in the deployment pipeline.
