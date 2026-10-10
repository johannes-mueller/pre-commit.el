# pre-commit.el

An Emacs frontend for the [pre-commit](https://pre-commit.com) tool


## Synopsis

`pre-commit.el` provides functions and a transient interface to run
`pre-commit` commands.

Use the command `pre-commit-dispatch` to get a transient menu to run the
`pre-commit` tool.

You can choose the hook you want to run and if you want to run it on all files,
the current file or only the uncommitted changes.


## Install

You can install the package by adding the following into your emacs init file.

```elisp
(use-package pre-commit
  :vc (:url "https://github.com/johannes-mueller/pre-commit.el"
	    :branch "main" :rev :newest))
```

## Commands

The following commands are available:

* `pre-commit-run` is the general command to run `pre-commit`. It takes a list
  of arguments which are simply passed to the `pre-commit` command. If called
  interactively it simply calls `pre-commit run`.

* `pre-commit-run-hook` runs only one hook. If called interactively it prompts
  you with a selection of available hooks.

* `pre-commit-run-on-file` runs all hooks on the file given in the argument. If
  called interactively it runs all hooks on the current file.

* `pre-commit-run-hook-on-file` runs only one hook on a file. If called
  interactively it prompts you with a selection of available hooks.

* `pre-commit-repeat` repeats the last `pre-commit` run that has been performed
  for the current project.

* `pre-commit-autoupdate` to auto-update pre-commit config to the latest repos'
  versions like `pre-commit autoupdate`.

* `pre-commit-clean` to clean out pre-commit files like `pre-commit clean`.

* `pre-commit-validate-config` to validate .pre-commit-config.yaml files like
  `pre-commit validate-config`.

## Public API

The following functions are part of the public API and may be used by other
packages:

* `pre-commit-available-hooks` returns the sorted list of unique hook IDs
  defined in the pre-commit configuration of the current project.


## Configuration

The following configuration variables are available

* `pre-commit-command` the path to the `pre-commit` executable.


## Status

This is the result of an afternoon of agentic coding. Now up for the first real
life testing.


## Contributing

You are welcome to contribute to this project. Please use the clean code
principles and write short single-purpose functions. Furthermore use test
driven development and add your
[ERT](https://www.gnu.org/software/emacs/manual/html_mono/ert.html) style tests
to `tests/pre-commit.el-test.el`.  A convenient way to perform the tests
is the `eldev` tool. You can simply run

```
eldev test
```

Avoid making assumptions about internal variables and functions. Ideally the
unit tests should not contain any `pre-commit--…` references.

Please add a note about your changes in `CHANGELOG.md` in the "Unreleased"
section.
