# Security

This repository has no runtime application surface. `go-standards/SKILL.md` and `go-standards/references/*.md` are read by a model, not executed; the only executable code is the shell scripts under `scripts/`, run manually or in CI.

## Scope

In scope:

- Prompt injection or harmful instructions in `go-standards/SKILL.md` or `go-standards/references/*.md`.
- Incorrect security guidance in skill content.
- Secrets, credentials, or private project data in examples or documentation.
- Changes under `scripts/` that do something other than what the script claims.

Out of scope:

- Vulnerabilities in tools or languages that a skill describes.
- Behavior of model providers or agent clients that load a published skill.
- Issues in repositories outside this one.

## Reporting

In-scope risks are caught by reviewing the diff before merge, the same as any other change. Report a vulnerability through GitHub private vulnerability reporting: open the repository's Security tab and select "Report a vulnerability". Do not open a public issue for an in-scope risk. Include the details below.

Include as much of this as applies:

- Affected file and line.
- Impact and who is affected.
- A minimal reproduction, or the quoted instruction or snippet.
- A suggested fix.

Do not include credentials, tokens, personal paths, or private project data. Reports are reviewed on a best-effort basis. There is no guaranteed response time or fix deadline.

## Safe use

Review skill instructions before loading them into an agent. Run scripts under `scripts/` only from trusted sources. Use placeholders instead of real credentials in examples.
