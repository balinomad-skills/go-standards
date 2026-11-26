# Contributing

This repository publishes one Agent Skill under `go-standards/`. A skill is valid with only `go-standards/SKILL.md`. A skill may also include `references/*.md` files that a model reads on demand. Repository files stay outside that folder. Contributions follow the same structural conventions the skill enforces on itself.

## Before opening a pull request

- Search existing issues first. Open an issue before a large change, so the scope can be agreed before the work is done.
- Keep each pull request to one concern. A content change and a repository tooling change belong in separate pull requests.
- **A wrong or outdated claim**: open an issue first if you are not certain of the fix, a pull request directly if you are. Cite a source (a release note, official documentation) for anything version-specific.
- **Missing coverage**: open an issue describing the gap before writing the content, so the scope can be agreed before the work is done.
- **Style or formatting only**: fine to submit directly.
- Do not assert a tool behaviour or a rule effect without a citation, an executed check, or a direct artifact.
- Do not include credentials, tokens, personal paths, or private project data in issues, pull requests, tests, or commits.

## Structural rules this project holds itself to

- Each file under `references/` covers exactly one topic. If a change spans two topics, split it across two files.
- Every `references/*.md` file has a row in `SKILL.md`'s routing table. Adding a new reference file without a routing row is treated as incomplete.
- Rules are stated imperatively ("Always...", "Never...") with a concrete example, a good and bad pair where practical. A rule with no measurable condition is not a rule: "write clean code" fails this, "keep cyclomatic complexity under 15" passes.
- No content is duplicated between two reference files, or between the `SKILL.md` body and a reference file. If two files need the same rule, one owns it and the other cross-references it.
- `go-standards/SKILL.md`'s `name:` field matches the folder it lives in, exactly. A mismatch breaks skill discovery silently, with nothing to point at when it happens.
- `SKILL.md`'s `description:` states the trigger condition in its first sentence, and includes at least one explicit exclusion ("Does not apply to...").
- `SKILL.md`'s body stays under 500 lines. Anything longer belongs in `references/`, loaded on demand, not in the file every session pays for whether it is needed or not.

## Markdown conventions

- Use one H1 per file.
- Fence code blocks and name the language.
- Use `-` for unordered lists.
- Do not use em dashes.
- Keep each paragraph on one source line. Do not wrap prose manually.
- Do not use horizontal rules between sections.
- Do not use bold text as a heading substitute.

CI runs three mechanical checks on every pull request. You run one structural check locally and CI runs the other checks automatically.

| Check            | What it verifies                                                                      | Failure meaning                                             |
| ---------------- | ------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| ShellCheck       | Shell syntax and common mistakes in `scripts/*.sh`.                                   | A copied script may fail at runtime or behave unexpectedly. |
| Structural check | `SKILL.md` frontmatter, routing rows, and cross-references when `references/` exists. | The skill structure or its reference links are invalid.     |
| Link check       | Markdown links across the repository.                                                 | A link points to a missing target.                          |

CI does not check content accuracy, duplication, SKILL.md body length, naming, description rules, or Markdown style. Those are a human review step.

## Review

Pull requests are reviewed against this project's own skill-assessment criteria before merge (trigger design, scope, inter-file overlap, routing, content quality). This can take a few days for anything beyond a small factual fix.

## Documentation changes

Update `CHANGELOG.md`, `README.md`, and relevant docs when a change affects users. State what changed and why. If no documentation change is needed, note that in the pull request.

## Versioning

This skill follows [Semantic Versioning](https://semver.org/). `metadata.version` in `go-standards/SKILL.md` holds the bare version, for example `1.0.0`, with no `v` prefix. Release tags add the prefix, for example `v1.0.0`.

- **MAJOR**: guidance that users depend on is removed or reversed, or the routing and always-on behaviour changes in a way that invalidates results produced under the previous version.
- **MINOR**: new guidance, a new reference file, or new task coverage is added without invalidating existing behaviour.
- **PATCH**: a correction that does not change what the skill tells a model to do, such as a typo, a broken link, or a factually wrong claim.

Record the version in `CHANGELOG.md` in the same pull request. The release tag and the `metadata.version` value must describe the same release.

## Verifying a change before submitting

```bash
bash scripts/structural-check.sh
```

This runs the structural check described above. It checks `SKILL.md` frontmatter and, when `references/` exists, routing rows and cross-references. A single `SKILL.md` with no `references/` directory is valid. Fix whatever the check reports before opening the pull request. CI runs ShellCheck, the structural check, and the link check on the pull request.
