# AGENTS.md

Guidance for AI agents and contributors working on pre-commit.el.

## Project Overview

An Emacs frontend for the [pre-commit](https://pre-commit.com) tool.
Runs pre-commit commands from Emacs via a transient dispatch menu and
interactive functions.

## Requirements

- **Emacs >= 30.1** (uses `if-let*`, `when-let*`; no `if-let`/`when-let`)
- **transient >= 0.10.1** (for `pre-commit-dispatch`; the `:remember-value`
  prefix slot needs 0.10.0, and 0.10.1 fixes `transient--get-savable-value`
  while exiting, see transient issue #410)

## Architecture

| Layer | Prefix | Visibility |
|-------|--------|------------|
| Public commands | `pre-commit-` | Documented in README |
| Internal helpers | `pre-commit--` | Not part of the public API |

### File layout

- `pre-commit.el` — entire implementation (single file)
- `tests/pre-commit.el-test.el` — ERT tests using `mocker` and `cl-letf`
- `Eldev` — build/test configuration
- `CHANGELOG.md` — keep-a-changelog format

## Code Conventions

### Clean code principles

- **Short, single-purpose functions** — each function does one thing.
  Target <= 15–20 lines; extract helpers when a function grows.
- **One level of abstraction per function** — public commands orchestrate
  (read input → delegate); helpers do the mechanics.
- **No duplication** — one canonical builder for arg lists / command lines
  shared by all commands and dispatch suffixes.
- **Pure helpers where possible** — parsing/formatting helpers take explicit
  arguments and return values; only stateful helpers touch globals/processes.
- Internal helpers use `pre-commit--` prefix; public functions use `pre-commit-`.

### Emacs Lisp conventions

- Use `if-let*`/`when-let*` for nil-handling (Emacs 30.1+); never `if-let`/`when-let`.
- Docstrings: first line is a complete sentence; two spaces after periods;
  quote Lisp symbols with `` ` `` (e.g. `` `buffer-file-name' ``).
- Byte-compile must be warning-free.

## Testing

### Running tests

```sh
eldev test          # run tests
eldev compile       # byte-compile
eldev lint package-lint
eldev lint relint
eldev lint checkdoc
```

### Test conventions

- Tests interact with production code **only via public functions/variables**.
  No references to `pre-commit--*` internals.
- Use `with-temp-git-repo` macro (defined in test file) to create real
  temporary git repos — a `.git` directory suffices for `vc-git-root` to
  detect the repo; no need to run `git init`.
- Mock external boundaries (`compile`, `completing-read`) with `cl-letf`.
- `pre-commit-repeat` state is set up by calling `pre-commit-run` first,
  not by directly manipulating the last-command table.
- Tests use `with-temp-buffer` + `write-region` to write config files inside
  the temp repo.

### Public API covered by tests

- `pre-commit-available-hooks`
- `pre-commit-run` (interactive + non-interactive)
- `pre-commit-run-hook` (interactive + non-interactive)
- `pre-commit-run-on-file` (interactive + non-interactive)
- `pre-commit-run-hook-on-file` (interactive + non-interactive)
- `pre-commit-repeat` (replays last run, errors when none recorded)
- `pre-commit-autoupdate` (non-interactive, errors outside a git repo)
- `pre-commit-validate-config` (non-interactive, `.yaml`/`.yml` lookup, errors
  when no config file exists)

## pre-commit CLI mapping

| Action | Command line |
|--------|-------------|
| Uncommitted changes | `pre-commit run` |
| All files | `pre-commit run --all-files` |
| Current file | `pre-commit run --files <file>` |
| Single hook | `pre-commit run <hook>` |
| Single hook on file | `pre-commit run <hook> --files <file>` |
| Autoupdate | `pre-commit autoupdate` |
| Validate config | `pre-commit validate-config <config>` |

## Hook discovery

Hooks are discovered by parsing `.pre-commit-config.yaml` (preferred) or
`.pre-commit-config.yml` for `- id: <name>` lines. No CLI call to pre-commit.
