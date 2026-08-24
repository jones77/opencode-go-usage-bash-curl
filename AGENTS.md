# Agent Guidelines for `opencode-go-usage.sh`

## Language and runtime

- Target `bash` 4.x+ with `#!/usr/bin/env bash`.
- Prefer `[[ ... ]]` for conditional tests and `(( ... ))` for arithmetic.

## Function naming

All functions in this project are internal to a single self-contained script,
so function names use plain `snake_case` with **no leading underscore**.
This includes the entry point, which is named `main`
and invoked only when the script is executed directly (not when sourced):

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
    main "$@"
fi
```

Keep helper functions small,
use `local` for all function variables,
and mark top-level constants `readonly`.

The leading-underscore convention is reserved for **module-private
shared-state variables** (for example `_period`, `_percent`, `_duration`,
`_use_color`, `_short_mode`) and read-only metadata constants
(`_optstring`, `_long_alias`); it is *not* applied to function names.

## Control-flow style

Use the **POSIX/Bourne** style for compound commands:
put `then` and `do` on their own lines
rather than on the same line as `if`, `for`, `while`, or `until`.

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

Per the GNU Bash manual:

> Note that wherever a `;` appears in the description of a command's syntax,
> it may be replaced with one or more newlines.

It also avoids sprinkling semicolons through multi-line control structures.
`else`, `elif`, `fi`, and `done` remain on their own lines.

## Variable naming

- Local/script variables: `lower_snake_case`.
- Declare associative arrays with `readonly -A` when appropriate.

## Formatting

- Indent with 4 spaces.
- Keep lines 80 characters long;
  break long pipelines with `\` and a leading pipe on continuation lines.
  - But do not break hyperlinks, they can be as long as they need to be.
- Do not use the `function` keyword; use `name() { ... }`.
- Place `||` and `&&` at the **start** of continuation lines, not at the end
  of the preceding line. This makes the operators stand out visually:

  ```bash
  [[ -f "$file" ]] \
      && process "$file"
  ```

## ShellCheck

The script is expected to pass `shellcheck`.

## `set -e` and `&&` chains as the last statement of a function

This is not obvious to human users.

A `&&` chain short-circuits: if the left side fails, the right side
never runs, and the chain returns the left side's exit status (non-zero).
A function's return value is the exit status of its last command.
So when a `&&` chain is the **last statement** in a function,
the function inherits that non-zero status even in the normal (non-error) case.

With `set -e`, a function called as a standalone statement
(not under `if`, `while`, `&&`, or `||`)
that returns non-zero kills the script — silently.

The `&&` chain itself is fine; `set -e` does not fire on commands
*inside* a `&&`/`||` list. The problem is purely the function's
return value leaking out.

Alert the user to these problems when you spot them.

## Testing

Core, pure functions are tested in `test_opencode-go-usage.sh`:
the progress-bar `bar` renderer, `format_duration`, `duration_from_iso8601`,
`human_readable` / `human_readable_short` (with `seconds_until_iso` stubbed
for a deterministic clock), `format_entry`, `parse_args`, `apply_option`,
`validate_width`, `parse_usage_json`, and `render_output`.

The test file sources the main script through the entry-point guard
and runs a small built-in harness. Output is TAP-formatted
(`ok N - name` / `not ok N - name` with a trailing `1..N` plan and
`#`-prefixed diagnostics) so it can be consumed by `prove`/`yath`.
The harness exits non-zero if any assertion failed.

## Terminal rendering assumptions

All characters used for progress bars and help-text diagrams
(including box-drawing/block-fill glyphs such as `█`, `▄`, `▌`, `▁`,
`░`, `▒`, `▓`, and the empty marker `␣`) are assumed to render as
**single-width** glyphs in the target terminal.

Do not introduce characters whose display width depends on locale or
terminal configuration (for example, CJK codepoints or other
ambiguous-width characters); keep every output character single-width
so that `printf` field widths align visually.

Note also that `bash`/`coreutils` `printf` field widths count **bytes**,
not characters. The glyphs above are 3-byte UTF-8 characters, so a
width specifier like `%-17s` pads to 17 bytes, not 17 characters.
When aligning multibyte output, compute padding explicitly (e.g. with
`%*s` and a character-based count) rather than relying on `%Ns`.

## OpenSpec

This repo is intentionally kept as a single self-contained shell script.
We do not maintain an `openspec/changes/` directory for refactors that stay
within `opencode-go-usage.sh`; such changes are treated as a direct-user-override
of the usual OpenSpec gate.
