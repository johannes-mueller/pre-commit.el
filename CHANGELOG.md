# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- Initial implementation of `pre-commit.el`, an Emacs frontend for the
  `pre-commit` tool.
- Commands: `pre-commit-run`, `pre-commit-run-hook`,
  `pre-commit-run-on-file`, `pre-commit-run-hook-on-file`,
  `pre-commit-repeat`.
- Customization variable `pre-commit-command`.
- Transient dispatch menu `pre-commit-dispatch`.
- Hook selection by parsing `.pre-commit-config.yaml` / `.yml`.
- Test suite with ERT.
- Commands `pre-commit-autoupdate` and `pre-commit-validate-config`, wired
  into `pre-commit-dispatch` under a new "Maintenance" column, disabled when
  no pre-commit config file exists.
- Customization variable `pre-commit-use-color` to control colored output
  (default: `t`). When non-nil, `--color=always' is passed to pre-commit;
  when nil, `--color=never' is passed.
- Verbose switch (`-v`), available in `pre-commit-dispatch` under "Options".
  When enabled, `--verbose` is passed as an argument to the `pre-commit run`
  commands invoked from the transient.

### Fixed

- Declare the `transient` dependency (>= 0.10.1).  The verbose switch uses
  `:remember-value 'export`, which requires transient 0.10.0+, while Emacs 30
  bundles an older transient; without the explicit dependency the package
  failed to load there.

### Changed
