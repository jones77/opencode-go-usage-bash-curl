#!/usr/bin/env bash
# Core tests for opencode-go-usage.sh.
# Focus on deterministic internals (bar cells/steps, duration formatting),
# not full output layouts which are brittle.
set -uo pipefail
# Do not use set -e; assertions collect failures via ||.

# shellcheck source=/dev/null
source ./opencode-go-usage.sh

pass=0
fail=0

assert_eq() {
    local expected="$1" actual="$2" name="$3"
    if [[ "$expected" == "$actual" ]]
    then
        pass=$((pass + 1))
        echo "ok - $name"
    else
        fail=$((fail + 1))
        echo "not ok - $name"
        printf '  expected: %q\n' "$expected"
        printf '  actual:   %q\n' "$actual"
    fi
}

assert_bar_width() {
    local percent="$1" width="$2" name="$3"
    local output
    output=$(_bar "$percent" "$width")
    if (( ${#output} == width ))
    then
        pass=$((pass + 1))
        echo "ok - $name"
    else
        fail=$((fail + 1))
        echo "not ok - $name"
        printf '  expected width: %d\n' "$width"
        printf '  actual width:   %d (%q)\n' "${#output}" "$output"
    fi
}

assert_bar_chars_valid() {
    local percent="$1" width="$2" name="$3"
    local output bad
    output=$(_bar "$percent" "$width")
    bad=$(printf '%s' "$output" | tr -d '⎼▁▂▃▄▅▆▇█')
    if [[ -z "$bad" ]]
    then
        pass=$((pass + 1))
        echo "ok - $name"
    else
        fail=$((fail + 1))
        echo "not ok - $name"
        printf '  unexpected chars: %q\n' "$bad"
    fi
}

# _bar: width 1 spot checks across the 8 steps.
assert_eq "⎼" "$(_bar 0 1)"   "_bar 0% width 1 (empty)"
assert_eq "▁" "$(_bar 13 1)"  "_bar ~13% width 1 (step 1)"
assert_eq "▂" "$(_bar 25 1)"  "_bar ~25% width 1 (step 2)"
assert_eq "▄" "$(_bar 50 1)"  "_bar ~50% width 1 (step 4)"
assert_eq "█" "$(_bar 100 1)" "_bar 100% width 1 (full)"

# _bar: clamping above 100%.
assert_eq "█" "$(_bar 200 1)" "_bar 200% width 1 (clamp)"

# _bar: width boundaries at empty/full.
for width in 1 2 3 4 5 6 7 8 9 10 11 12 13
do
    assert_bar_width 0 "$width" "_bar 0% width $width length"
    assert_bar_width 100 "$width" "_bar 100% width $width length"
done

# _bar: valid character set for a spread of percents/widths.
for width in 1 2 4 8 13
 do
    for percent in 0 1 12 25 37 50 63 75 87 99 100
    do
        assert_bar_chars_valid "$percent" "$width" "_bar chars valid $percent% width $width"
    done
done

# _bar: a specific multi-cell layout (matches the usage table).
assert_eq "██████▄⎼⎼⎼⎼⎼⎼" "$(_bar 50 13)" "_bar 50% width 13 layout"

# _format_duration: pure formatting logic.
assert_eq ""                 "$(_format_duration 0 0 0 0)" "_format_duration all zero"
assert_eq " 1d  2h  3m  4s"   "$(_format_duration 1 2 3 4)" "_format_duration 1d2h3m4s"
assert_eq " 1h  1s"           "$(_format_duration 0 1 0 1)" "_format_duration skip zero units"
assert_eq " 5d"              "$(_format_duration 5 0 0 0)" "_format_duration days only"

echo ""
echo "passed: $pass  failed: $fail"
exit "$fail"
