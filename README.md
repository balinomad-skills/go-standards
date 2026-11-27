# go-standards

[![CI](https://github.com/balinomad-skills/go-standards/actions/workflows/ci.yml/badge.svg)](https://github.com/balinomad-skills/go-standards/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/balinomad-skills/go-standards)](https://github.com/balinomad-skills/go-standards/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Triggers on all Go coding tasks: writing, reviewing, debugging, improving, or discussing the design of Go code, whether or not any file or code is produced. Applies idiomatic Go standards: error handling, naming, concurrency, interfaces, generics, performance, security, testing, HTTP services, database access, encoding, CLI applications, configuration, build/distribution, tooling, and CI for Go projects. Also triggers when .go files, go.mod, or go.sum are present. Keywords: golang, goroutine, go module, Go project, Go service, generics, net/http, database/sql, encoding/json. Does not apply to general software engineering questions that mention Go incidentally, or to non-Go code in a mixed-language project.

Reviewed against Go 1.27.4 (2026-11-10).

## Install

### Claude Code

Download `go-standards.zip` from the [latest release](https://github.com/balinomad-skills/go-standards/releases/latest), then unzip it into your skills folder. The ZIP contains only the skill folder, with no repository files.

```bash
unzip go-standards.zip -d ~/.claude/skills
```

### skills.sh

```bash
npx skills add balinomad-skills/go-standards
```

Requires Node.js with `npx`. The command installs from the repository's default branch, not from the release ZIP. It defaults to project scope. Add `-g` to install for all projects. Add `-a` to target specific agents.

`npx skills update go-standards` keeps the skill up‑to‑date from the repository's default branch.

### SkillMD

```bash
npx get-skill add balinomad/go-standards
```

Requires Node.js with `npx`. The command installs the full skill folder, including references. It asks whether to install for the current project or for all projects. Add `-p` to install for the current project. Add `-g` to install for all projects. Add `-a` to target specific agents.

`npx get-skill update go-standards` keeps the skill up to date from SkillMD.

### claude.ai

Download `go-standards.zip` from the [latest release](https://github.com/balinomad-skills/go-standards/releases/latest), then upload it under Customize > Skills.

### Other agents that read the Agent Skills format

Copy the `go-standards/` folder from the release ZIP or from the repository to wherever that tool looks for skills. Do not install the repository files as the skill.

### No file upload or skill support

Download `go-standards.txt` from the [latest release](https://github.com/balinomad-skills/go-standards/releases/latest). It flattens this skill into one document for any chat-based LLM with no file-upload or skill-execution support, not only Claude.

Paste the block below as the message itself, with the full contents of the downloaded `go-standards.txt` immediately after it, in the same message. The quoted block is a wrapper issued by you, not a copy of the embedded block.

> Ingest the provided skill content. Parse the custom boundaries to reconstruct the directory structure. Treat `SKILL.md` and all enclosed files as your strict operational baseline for this entire session. Evaluate `SKILL.md` for any initialization protocol, preflight check, or starting instruction. If present, execute it immediately as your first response. If absent, acknowledge ingestion and wait for my next instruction.

## What's inside

An always-on standard for Go code, from a single function to a released service.

- Always-on rules: gofmt or gofumpt formatting, explicit error handling, and no panic in library code
- Writing new Go code: error handling and naming
- Reviewing, improving, or debugging Go code: review checks and known pitfalls
- Concurrency: goroutines, channels, context, and worker pools
- Interface design: functional options and struct embedding
- Generics: type parameters, constraints, and reflection
- Project and module layout
- Performance: allocations and profiling
- Security: input validation and cryptography
- Testing: benchmarks, fuzz tests, mocking, and goroutine leak detection
- Tooling: linting configuration, library selection, and local development setup
- CI/CD: GitHub Actions, Dependabot, and GoReleaser
- Modernisation: new language features and standard-library upgrades
- Observability: structured logging, metrics, and tracing
- HTTP servers: routing, middleware, timeouts, and graceful shutdown
- Database access: connection pooling, transactions, and migrations
- JSON encoding: struct tags, custom marshalling, and streaming
- CLI applications: flag and Cobra, exit codes, and subcommands
- Configuration: environment variables and validation
- Build and distribution: build constraints, go:embed, cross-compilation, and module versioning

## Example prompts

- Review the Go handlers under `internal/api` for ignored errors, missing context propagation, and gaps in graceful shutdown, then list the fixes in priority order.
- Add a generic LRU cache to this Go module with a typed constraint, plus a benchmark that proves the hot path does not allocate.
- Our `database/sql` code opens a new `*sql.DB` per request and commits transactions without checking the context. Show the corrected connection pooling and transaction handling.

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md). Released under the MIT license, see [LICENSE](LICENSE).
