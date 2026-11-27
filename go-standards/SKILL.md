---
name: go-standards
description: |
    Triggers on all Go coding tasks: writing, reviewing, debugging, improving, or discussing the design of Go code, whether or not any file or code is produced. Applies idiomatic Go standards: error handling, naming, concurrency, interfaces, generics, performance, security, testing, HTTP services, database access, encoding, CLI applications, configuration, build/distribution, tooling, and CI for Go projects. Also triggers when .go files, go.mod, or go.sum are present. Keywords: golang, goroutine, go module, Go project, Go service, generics, net/http, database/sql, encoding/json. Does not apply to general software engineering questions that mention Go incidentally, or to non-Go code in a mixed-language project.
license: MIT
metadata:
    version: 1.1.0
    updated: 2026-11-27
    go_reviewed: 1.27.4
    tags: [code, go]
---

# Go/Golang Standards

## Scope

This skill covers Go source code and the Go-specific project files that build, lint, test, and release it. For documentation formatting, follow the repository's Markdown conventions. For architecture decisions that span languages, apply this skill only to the Go components. This skill covers only the Go-side API usage in `references/database.md` (connection handling, context propagation, transactions, scanning), not SQL query design, schema design, or query performance tuning.

Coverage baseline: Go 1.21 through Go 1.27, reviewed against Go 1.27.4 (2026-11-10).

## Behaviour (always applies)

- `Always` and `Never` are mandatory. `Prefer` is a recommendation. Declarative rules are requirements. Do not use `should` to state a requirement.
- Skip Go basics unless asked.
- Remove trailing whitespace from output. No redundant blank lines in code blocks.
- If a request can be answered correctly without clarification, answer it. Ask only when the missing information affects correctness, behaviour, or API design. When you must ask:
    1. State the blocking question(s) explicitly.
    2. Explain briefly why it matters and what it affects.
    3. List options with trade-offs and a recommended default.

Wait for confirmation before applying any assumption-driven change.

## Initialization Protocol (Delegated)

The session-start protocol is strictly delegated to `references/project-context.md`. Immediately read and follow that file in its entirety to establish the operational baseline.

## Reference files: load based on task

| Task                                                                                 | Read                                                                                                        |
| ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| Writing new Go code (any topic)                                                      | `references/error-handling.md` + `references/naming.md`                                                     |
| Reviewing, improving, or debugging existing Go code                                  | `references/error-handling.md` + `references/naming.md` + `references/review.md` + `references/pitfalls.md` |
| Concurrency, goroutines, channels, context, worker pools                             | `references/concurrency.md`                                                                                 |
| API design, interface patterns, functional options, struct embedding                 | `references/interfaces.md`                                                                                  |
| Generics, type parameters, constraints, reflection                                   | `references/generics-and-reflection.md`                                                                     |
| New project or module layout                                                         | `references/project-structure.md`                                                                           |
| Performance, allocations, profiling                                                  | `references/performance.md`                                                                                 |
| Security, input validation, crypto                                                   | `references/security.md`                                                                                    |
| Tests, benchmarks, fuzz tests, mocking, goroutine leak detection                     | `references/testing.md`                                                                                     |
| Toolchain selection (`go`/`toolchain`, `GOTOOLCHAIN`), linting, libraries, local dev | `references/toolchain.md`                                                                                   |
| CI/CD pipeline authoring, GitHub Actions workflows, Dependabot, GoReleaser           | `references/ci.md`                                                                                          |
| Modernising Go code, new language features, stdlib upgrades                          | `references/modernize.md`                                                                                   |
| Observability, structured logging, metrics, tracing                                  | `references/observability.md`                                                                               |
| HTTP servers, ServeMux routing, middleware, timeouts, graceful shutdown              | `references/http-and-servers.md`                                                                            |
| Database access, database/sql, connection pooling, transactions, migrations          | `references/database.md`                                                                                    |
| JSON encoding, struct tags, custom marshalling, streaming                            | `references/encoding.md`                                                                                    |
| CLI applications, flag/Cobra, exit codes, subcommands                                | `references/cli-applications.md`                                                                            |
| Configuration loading, environment variables, config validation                      | `references/configuration.md`                                                                               |
| Build constraints, go:embed, cross-compilation, module versioning                    | `references/build-and-distribution.md`                                                                      |
| Session-start version protocol, release context                                      | `references/project-context.md`                                                                             |
| General Go question with no identifiable topic                                       | `references/naming.md` only                                                                                 |

Load only what the task requires. Never pre-load all files. The first two rows are base rows; a topic row applies in addition to the base row for the same task, not instead of it.

## Rules that always apply

- Format with `gofmt` or `gofumpt`. Never produce unformatted output.
- End every Go file with exactly one newline. No trailing blank lines after the final line.
- Errors are values. Handle explicitly; never discard with `_` silently.
- No `panic` in library code.
