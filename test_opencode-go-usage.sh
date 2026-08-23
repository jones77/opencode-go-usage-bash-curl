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
    local percent="$1" width="$2" name="$3" style="${4:-vertical}"
    local output
    output=$(_bar "$percent" "$width" "$style")
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
    local percent="$1" width="$2" name="$3" style="${4:-vertical}"
    local output bad valid
    output=$(_bar "$percent" "$width" "$style")
    case "$style" in
        vertical)   valid='␣▁▂▃▄▅▆▇█' ;;
        horizontal) valid='␣▏▎▍▌▋▊▉█' ;;
        gradient)   valid='␣░▒▓█' ;;
        *)          valid='' ;;
    esac
    bad=$(printf '%s' "$output" | tr -d "$valid")
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
assert_eq "␣" "$(_bar 0 1)"   "_bar 0% width 1 (empty)"
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
assert_eq "██████▄␣␣␣␣␣␣" "$(_bar 50 13)" "_bar 50% width 13 layout"

# _bar: horizontal style spot checks.
assert_eq "␣" "$(_bar 0 1 horizontal)"   "_bar horizontal 0% width 1 (empty)"
assert_eq "▏" "$(_bar 13 1 horizontal)"  "_bar horizontal ~13% width 1 (step 1)"
assert_eq "▎" "$(_bar 25 1 horizontal)"  "_bar horizontal ~25% width 1 (step 2)"
assert_eq "▌" "$(_bar 50 1 horizontal)"  "_bar horizontal ~50% width 1 (step 4)"
assert_eq "█" "$(_bar 100 1 horizontal)" "_bar horizontal 100% width 1 (full)"
assert_eq "██████▌␣␣␣␣␣␣" "$(_bar 50 13 horizontal)" \
    "_bar horizontal 50% width 13 layout"

# _bar: gradient style spot checks.
assert_eq "␣" "$(_bar 0 1 gradient)"     "_bar gradient 0% width 1 (empty)"
assert_eq "░" "$(_bar 25 1 gradient)"    "_bar gradient 25% width 1 (step 1)"
assert_eq "▒" "$(_bar 50 1 gradient)"    "_bar gradient 50% width 1 (step 2)"
assert_eq "▓" "$(_bar 75 1 gradient)"    "_bar gradient 75% width 1 (step 3)"
assert_eq "█" "$(_bar 100 1 gradient)"   "_bar gradient 100% width 1 (full)"
assert_eq "██████▒␣␣␣␣␣␣" "$(_bar 50 13 gradient)" \
    "_bar gradient 50% width 13 layout"

# _bar: width boundaries at empty/full for all styles.
for style in vertical horizontal gradient
 do
    for width in 1 2 3 4 5 6 7 8 9 10 11 12 13
    do
        assert_bar_width 0 "$width" "_bar $style 0% width $width length" "$style"
        assert_bar_width 100 "$width" "_bar $style 100% width $width length" "$style"
    done
done

# _bar: valid character set for a spread of percents/widths for all styles.
for style in vertical horizontal gradient
 do
    for width in 1 2 4 8 13
    do
        for percent in 0 1 12 25 37 50 63 75 87 99 100
        do
            assert_bar_chars_valid "$percent" "$width" \
                "_bar $style chars valid $percent% width $width" "$style"
        done
    done
done

# _format_duration: pure formatting logic.
assert_eq ""                 "$(_format_duration 0 0 0 0)" "_format_duration all zero"
assert_eq " 1d  2h  3m  4s"   "$(_format_duration 1 2 3 4)" "_format_duration 1d2h3m4s"
assert_eq " 1h  1s"           "$(_format_duration 0 1 0 1)" "_format_duration skip zero units"
assert_eq " 5d"              "$(_format_duration 5 0 0 0)" "_format_duration days only"

# _format_entry: numbers and --only-* modes.
# Signature: period percent duration_text short one_line width color \
#            numbers_mode bar_style only_mode
assert_eq "rolling 50 12345" \
    "$(_format_entry "rolling" 50 "12345" false false 0 false true "vertical" "none")" \
    "_format_entry numbers full"
assert_eq "50   12345" \
    "$(_format_entry "rolling" 50 "12345" true false 0 false true "vertical" "none")" \
    "_format_entry numbers short"
assert_eq "50 12345" \
    "$(_format_entry "rolling" 50 "12345" false true 0 false true "vertical" "none")" \
    "_format_entry numbers one-line"
assert_eq "50% 12345" \
    "$(_format_entry "rolling" 50 "12345" false true 0 false false "vertical" "none")" \
    "_format_entry one-line"
assert_eq "$(printf '\033[38;5;27m 50  12345\033[39m')" \
    "$(_format_entry "rolling" 50 "12345" false true 0 true true "vertical" "none")" \
    "_format_entry numbers one-line color aligned"
assert_eq "$(printf '\033[38;5;27m 50%%  12345\033[39m')" \
    "$(_format_entry "rolling" 50 "12345" false true 0 true false "vertical" "none")" \
    "_format_entry one-line color aligned"

# _format_entry: numbers mode with a width-8 bar.
assert_eq "rolling 50 ████␣␣␣␣ 12345" \
    "$(_format_entry "rolling" 50 "12345" false false 8 false true "vertical" "none")" \
    "_format_entry numbers full with bar"

# _format_entry: --only-* modes.
assert_eq "██████▄␣␣␣␣␣␣" \
    "$(_format_entry "rolling" 50 "12345" false false 13 false false "vertical" "bar")" \
    "_format_entry only bar"
assert_eq "50%" \
    "$(_format_entry "rolling" 50 "" false false 0 false false "vertical" "percent")" \
    "_format_entry only percent"
assert_eq "50" \
    "$(_format_entry "rolling" 50 "" false false 0 false true "vertical" "percent")" \
    "_format_entry only percent with numbers"
assert_eq "$(printf '\033[38;5;27m 50%%\033[39m')" \
    "$(_format_entry "rolling" 50 "" false true 0 true false "vertical" "percent")" \
    "_format_entry only percent one-line color aligned"
assert_eq "12345" \
    "$(_format_entry "rolling" 50 "12345" false false 0 false false "vertical" "datetime")" \
    "_format_entry only datetime"
assert_eq "$(printf '\033[38;5;27m 12345\033[39m')" \
    "$(_format_entry "rolling" 50 "12345" false true 0 true false "vertical" "datetime")" \
    "_format_entry only datetime one-line color aligned"

# _parse_args: --only-* options can be combined with --short and --one-line.
mode=""
only_mode=""
one_line=""
date_mode=""
_parse_args --only-bar --short
assert_eq "bar" "$only_mode" "_parse_args --only-bar --short accepted"
assert_eq "short" "$mode" "_parse_args --only-bar --short mode"

_parse_args --only-bar --one-line
assert_eq "bar" "$only_mode" "_parse_args --only-bar --one-line accepted"
assert_eq "true" "$one_line" "_parse_args --only-bar --one-line one_line"

_parse_args --only-percent --short
assert_eq "percent" "$only_mode" "_parse_args --only-percent --short accepted"

_parse_args --only-datetime --one-line
assert_eq "datetime" "$only_mode" "_parse_args --only-datetime --one-line accepted"

_parse_args --only-bar --date
assert_eq "bar" "$only_mode" "_parse_args --only-bar --date accepted"
assert_eq "true" "$date_mode" "_parse_args --only-bar --date date_mode"

# _parse_args: --only-* options remain mutually exclusive with each other.
assert_args_fail() {
    local name="$1"
    shift
    if ./opencode-go-usage.sh "$@" >/dev/null 2>&1
    then
        fail=$((fail + 1))
        echo "not ok - $name"
    else
        pass=$((pass + 1))
        echo "ok - $name"
    fi
}

assert_args_fail "_parse_args rejects --only-bar --only-percent" --only-bar --only-percent
assert_args_fail "_parse_args rejects --only-percent --only-datetime" --only-percent --only-datetime
assert_args_fail "_parse_args rejects removed -r option" -r
assert_args_fail "_parse_args rejects removed --percent option" --percent

# _render_output: date prefix in one-line mode includes a comma.
# shellcheck disable=SC2329  # invoked indirectly through _render_output
_timestamp() { printf '%s' "2026-08-23T12:00:00"; }
# shellcheck disable=SC2329  # invoked indirectly through _render_output
_human_readable_short() { printf '%s' "FIXED"; }
output=$(printf 'rolling,21,2026-08-23T15:00:00Z\nweekly,55,2026-08-23T14:00:00Z\n' \
    | _render_output "full" "plain" "0" "true" "true" "false" "vertical" "none")
assert_eq "2026-08-23T12:00:00, 21% FIXED, 55% FIXED" "$output" \
    "_render_output one-line date prefix uses comma"

# _render_output: -d with -n uses epoch seconds for the timestamp prefix.
# shellcheck disable=SC2329  # invoked indirectly through _render_output
_seconds_until_iso() { printf '%s' "SECS"; }
# shellcheck disable=SC2329  # invoked indirectly through _render_output
_timestamp() { printf '%s' "1755950400"; }
output=$(printf 'rolling,21,2026-08-23T15:00:00Z\nweekly,55,2026-08-23T14:00:00Z\n' \
    | _render_output "full" "plain" "0" "false" "true" "true" "vertical" "none")
first_line="${output%%$'\n'*}"
assert_eq "1755950400 rolling 21 SECS" "$first_line" \
    "_render_output numbers date prefix uses epoch seconds"

# _render_output: -d -n -1 uses epoch seconds and a comma separator.
output=$(printf 'rolling,21,2026-08-23T15:00:00Z\nweekly,55,2026-08-23T14:00:00Z\n' \
    | _render_output "full" "plain" "0" "true" "true" "true" "vertical" "none")
assert_eq "1755950400, 21 SECS, 55 SECS" "$output" \
    "_render_output numbers one-line date prefix uses epoch seconds and comma"

# Restore the real functions.
unset -f _timestamp _human_readable_short _seconds_until_iso

echo ""
echo "passed: $pass  failed: $fail"
exit "$fail"
