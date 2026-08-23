# Agent Guidelines for `opencode-go-usage.sh`

## Language and runtime

- Target `bash` 4.x+ with `#!/usr/bin/env bash`.
- Start every script with `set -euo pipefail`.
- Use `$(...)` for command substitution; never backticks.
- Prefer `[[ ... ]]` for conditional tests and `(( ... ))` for arithmetic.

## Function naming

All functions in this project are internal to a single self-contained script,
so **every function name is prefixed with `_`** and uses `snake_case`.
This includes the entry point, which is named `_main`
and invoked only when the script is executed directly (not when sourced):

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
    _main "$@"
fi
```

Keep helper functions small, use `local` for all function variables,
and mark top-level constants `readonly`.

## Control-flow style

Use the **POSIX/Bourne** style for compound commands: put `then` and `do` on
their own lines rather than on the same line as `if`, `for`, `while`, or
`until`.

```bash
if [[ -n "$foo" ]]
then
    ...
fi

for unit in "d" "h" "m" "s"
do
    ...
done
```

This is explicitly allowed by the GNU Bash manual:

> Note that wherever a `;` appears in the description of a command's syntax,
> it may be replaced with one or more newlines.

It also avoids sprinkling semicolons through multi-line control structures.
`else`, `elif`, `fi`, and `done` remain on their own lines.

## Variable naming

- Local/script variables: `lower_snake_case`.
- Constants and exported/environment variables: `UPPER_SNAKE_CASE`.
- Declare associative arrays with `readonly -A` when appropriate.

## Formatting

- Indent with 4 spaces.
- Keep lines 80 characters long;
  break long pipelines with `\` and a leading pipe on continuation lines.
  - But do not break hyperlinks, they can be as long as they need to be.
- Do not use the `function` keyword; use `name() { ... }`.

## ShellCheck

The script is expected to pass `shellcheck`.
When a warning is a false positive or reflects an intentional pattern,
add a suppression comment with a brief justification on the same line
or immediately above the affected statement.

## Testing

Core, pure functions (especially the progress-bar `_bar` renderer)
are tested in `test_opencode-go-usage.sh`.
The test file sources the main script through the entry-point guard
and runs a small built-in harness.
Avoid brittle full-layout tests;
focus on cells, steps, and other deterministic internals.
