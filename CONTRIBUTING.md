# Contributing

Thanks for your interest in contributing to kiro-skills!

## Quick Start

1. Fork this repo
2. Create a branch (`git checkout -b feat/my-new-skill`)
3. Make your changes
4. Run validation: `bash scripts/validate-skills.sh`
5. Commit using conventional commits (see below)
6. Open a Pull Request

## Adding a New Skill

### Directory Structure

```
skills/my-skill-name/
├── SKILL.md              # Required
├── README.md             # Required for public skills
├── references/           # Optional: detailed docs
├── scripts/              # Optional: executable code
└── assets/               # Optional: templates, schemas
```

### SKILL.md Requirements

```yaml
---
name: my-skill-name          # lowercase, hyphens only, max 64 chars
description: |               # max 1024 chars
  What this skill does and when to trigger it.
  Include trigger keywords in the description.
license: MIT
---
```

- Body should be < 500 lines (for context window efficiency)
- Use progressive disclosure: keep SKILL.md focused, put details in `references/`

### Naming Convention

- Lowercase letters, numbers, and hyphens only
- Must not start or end with a hyphen
- Max 64 characters
- Descriptive: `kafka-msk` not `kafka`, `k8s-eks` not `kubernetes`

## Adding a Steering File

Place in `steering/` with appropriate frontmatter:

```yaml
---
inclusion: fileMatch
fileMatchPattern: '*.ts,*.tsx'
---
```

Inclusion types:
- `always` — loaded in every conversation (use sparingly)
- `fileMatch` — loaded when matching files are opened
- `manual` — loaded only when user references via `#`

## Commit Convention

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(skill): add kafka-msk skill
fix(steering): correct typescript-rules fileMatch pattern
docs: update README installation section
chore: update version.json
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`

Scopes (optional): `skill`, `steering`, `scripts`, `ci`

## Private vs Public

- Files/folders with `_` prefix are private (gitignored)
- Use `_` prefix for company-specific content
- Public template: `user-scope-config.example.md`
- Private actual: `_user-scope-config.md`

## Validation

Before submitting, ensure:

```bash
bash scripts/validate-skills.sh
```

This checks:
- SKILL.md exists in each skill directory
- Required frontmatter fields present
- Name format compliance
- Description length

## Code of Conduct

Be respectful. Focus on sharing useful domain knowledge.

## License

By contributing, you agree that your contributions will be licensed under MIT.
