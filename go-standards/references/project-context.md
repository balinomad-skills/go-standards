# Project Context: Session-Start Protocol

Execute Part 1 exactly ONCE upon ingestion to establish session constraints. Enforce Part 2 continuously for the duration of the session.

## PART 1: INITIALIZATION SEQUENCE

### Step 1: Detect Go version

Scan provided files in order of reliability:

| Source                  | What to read                         |
| ----------------------- | ------------------------------------ |
| `go.mod`                | `go 1.xx` directive (primary source) |
| `version.go` or similar | `const Version = "x.y.z"`            |
| Conversation            | Explicit statement by user           |

- **IF a version is detected:** Announce the detected version:
  > `[Source]`: go `[version]` detected.
- **IF no files are provided OR no version is detected:** Prompt the user:
  > No Go version detected. What is the minimum target version?

### Step 2: Detect version signals for breaking-changes

Scan for release context based ONLY on files currently provided. Sources in order:

| Source               | Signal                                                     |
| -------------------- | ---------------------------------------------------------- |
| `go.mod` module path | `/v2`, `/v3` suffix = major version in progress            |
| `CHANGELOG.md`       | Nearest version header (e.g. `## [2.0.0]` vs `## [1.4.2]`) |
| `version.go`         | Version constant value                                     |
| Conversation         | Explicit statements                                        |

**Interpreting conflicts & missing files:**

- IF `go.mod` has a suffix (e.g. `/v2`) + `CHANGELOG.md` last main release is less (e.g. `1.x`) → new major version
- IF `go.mod` has no suffix + previous version found in other files (e.g. `CHANGELOG.md`) → minor or patch
- IF no signals are found → ask without assumption

### Step 3: Ask the breaking-changes question

Ask only when the findings warrant it: when they establish a concrete version mode, announce it directly; when they leave the mode unresolved, ask explicitly. Cite the actual signals found. Never assume or invent data.

- **IF the signals point to major / greenfield:**
  > `[cite actual signals]`. This looks like a new major version. **Breaking changes enabled. Correct?**
- **IF the signals point to minor / patch:**
  > `[cite actual signals]`. This looks like a minor or patch release. **Breaking changes disabled. Correct?**
- **IF no signals:**
  > `No version signals found. **Breaking changes enabled or disabled for this session?**`

**If a question was asked, wait for the user to answer before proceeding to Step 4.**

### Step 4: Announce Go version mode [ON USER RESPONSE]

The breaking-changes answer drives the Go version upper bound default. Announce the full Go version settings immediately after the answer:
| Breaking changes             | Default Go version mode             |
| ---------------------------- | ----------------------------------- |
| Enabled (major / greenfield) | Non-strict · no upper bound         |
| Disabled (minor / patch)     | Non-strict · current stable ceiling |

**Announcement format:**

> `go [version] · non-strict · no upper bound` (major release)

> `go [version] · non-strict · up to current stable` (minor/patch release)

> `go [version] · strict` (if user declared strict)

User may override any axis at this point or at any time during the session.

## PART 2: CONTINUOUS OPERATIONAL RULES

### Rule 1: Go version mode behaviour

**Strict**: stay within the declared version. No suggestions requiring a higher version. Use when the deployment environment locks the version.

**Non-strict**: write code compatible with the declared version. When a newer version enables meaningfully better code, present the alternative in a separate block with a clear annotation. The primary solution always compiles on the declared version.

"Meaningfully better" means genuine improvement in correctness, safety, performance, or clarity, not cosmetic differences. Examples: generics (1.18), `slog` (1.21), loop variable capture fix (1.22), `iter` (1.23), `b.Loop()` in benchmarks (1.24).

**Output format for non-strict alternatives:**

```go
// go 1.21: compatible with declared version:
for _, u := range urls {
    u := u // capture loop variable
    go process(u)
}

// go 1.22 alternative: loop variable capture fixed, copy not needed:
for _, u := range urls {
    go process(u)
}
// Requires bumping go.mod to `go 1.22`. Recommend if upgrading is feasible.
```

### Rule 2: Session override

The user may change any setting at any time. Examples include:

- _"Enable breaking changes"_ / _"Disable breaking changes"_
- _"Switch to strict"_ / _"Non-strict, no upper bound"_
- _"Treat this as a minor release"_

Announce the change before continuing:

> `Breaking changes: <DISABLED/ENABLED> (session override). Go mode <changed/unchanged>: <version> · <strict/non-strict> · <ceiling>.`

### Rule 3: State Reconciliation (Late-Arriving Files)

If `.go`, `go.mod`, or `CHANGELOG.md` files are uploaded AFTER the initial session-start protocol has completed, immediately scan them for version signals. If the new files conflict with the established Go version or breaking-changes mode:

1. Halt analysis immediately.
2. Announce the conflict to the user.
3. Ask the user which state should take precedence.
