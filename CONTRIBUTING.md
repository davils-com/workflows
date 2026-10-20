# Contributing to davils-com/workflows

Thank you for helping. These workflows run in every repository of davils-com, so a change here
changes all of them: small, reviewed, tested changes are the rule.

## How to contribute

- **Bugs:** open an issue with the caller workflow, the configuration, a link to the failing run
  and what you expected.
- **Features:** open an issue first; describe the repository that needs it and the option you
  would add.
- **Security problems:** never in a public issue; see [SECURITY.md](SECURITY.md).
- **Pull requests:** branch from `develop`; `main` carries releases.

## Before you push

```bash
tools/lint.sh
tools/check-pins.sh
tools/check-dashes.sh
tools/gen-schema.sh && tools/gen-flutter-ci.sh && tools/gen-docs.sh
bats tests/scripts
```

CI runs the same checks (`self-lint.yml`) and calls every workflow on the fixtures
(`self-test.yml`). The [development guide](docs/topics/Development.md) explains the layout and
the conventions.

## Rules

- A new option starts in `actions/resolve-config/defaults.yaml`, with a default that keeps the
  current behaviour; the schema and the reference are generated from it.
- Every third-party action is pinned by its commit SHA with a version comment.
- Inputs, titles, branch names and other values reach scripts through environment variables only.
- Every job has `timeout-minutes` and only the permissions it needs.
- Removing an input or changing a default visibly is a breaking change for the next major version.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/): `feat(inspectra): ...`,
`fix(pages): ...`, `chore(deps): ...`. The type decides the next version and the changelog
section. Write in the present tense and use no em dashes.
