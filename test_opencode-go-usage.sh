#!/usr/bin/env bash
# Core tests for opencode-go-usage.sh.
# Focus on deterministic internals (bar cells/steps, duration formatting),
# not full output layouts which are brittle.
set -uo pipefail
# Do not use set -e; assertions collect failures via ||.

# shellcheck source=/dev/null
source ./opencode-go-usage.sh
set +e  # undo set -e inherited from the sourced script

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

# _duration_from_iso8601: past dates clamp to 0 instead of failing.
assert_eq "0 0 0 0" \
    "$(_duration_from_iso8601 "2020-01-01T00:00:00Z")" \
    "_duration_from_iso8601 past date clamps to zero"

# _format_entry: numbers and --only-* modes.
# Sets _-prefixed globals that _format_entry now reads.
_period="rolling" _percent=50 _duration_text="12345" \
    _short_mode=false one_line=false width=0 _use_color=false \
    numbers_mode=true bar_style="vertical" only_field="none"
assert_eq "rolling 50 12345" \
    "$(_format_entry)" \
    "_format_entry numbers full"

_period="rolling" _percent=50 _duration_text="12345" \
    _short_mode=true one_line=false width=0 _use_color=false \
    numbers_mode=true bar_style="vertical" only_field="none"
assert_eq "50   12345" \
    "$(_format_entry)" \
    "_format_entry numbers short"

_period="rolling" _percent=50 _duration_text="12345" \
    _short_mode=false one_line=true width=0 _use_color=false \
    numbers_mode=true bar_style="vertical" only_field="none"
assert_eq " 50  12345" \
    "$(_format_entry)" \
    "_format_entry numbers one-line"

_period="rolling" _percent=50 _duration_text="12345" \
    _short_mode=false one_line=true width=0 _use_color=false \
    numbers_mode=false bar_style="vertical" only_field="none"
assert_eq " 50%  12345" \
    "$(_format_entry)" \
    "_format_entry one-line"

_period="rolling" _percent=50 _duration_text="12345" \
    _short_mode=false one_line=true width=0 _use_color=true \
    numbers_mode=true bar_style="vertical" only_field="none"
assert_eq "$(printf '\033[38;5;27m 50  12345\033[39m')" \
    "$(_format_entry)" \
    "_format_entry numbers one-line color aligned"

_period="rolling" _percent=50 _duration_text="12345" \
    _short_mode=false one_line=true width=0 _use_color=true \
    numbers_mode=false bar_style="vertical" only_field="none"
assert_eq "$(printf '\033[38;5;27m 50%%  12345\033[39m')" \
    "$(_format_entry)" \
    "_format_entry one-line color aligned"

# _format_entry: numbers mode with a width-8 bar.
_period="rolling" _percent=50 _duration_text="12345" \
    _short_mode=false one_line=false width=8 _use_color=false \
    numbers_mode=true bar_style="vertical" only_field="none"
assert_eq "rolling 50 ████␣␣␣␣ 12345" \
    "$(_format_entry)" \
    "_format_entry numbers full with bar"

# _format_entry: --only-* modes.
_period="rolling" _percent=50 _duration_text="12345" \
    _short_mode=false one_line=false width=13 _use_color=false \
    numbers_mode=false bar_style="vertical" only_field="bar"
assert_eq "██████▄␣␣␣␣␣␣" \
    "$(_format_entry)" \
    "_format_entry only bar"

_period="rolling" _percent=50 _duration_text="" \
    _short_mode=false one_line=false width=0 _use_color=false \
    numbers_mode=false bar_style="vertical" only_field="percent"
assert_eq "50%" \
    "$(_format_entry)" \
    "_format_entry only percent"

_period="rolling" _percent=50 _duration_text="" \
    _short_mode=false one_line=false width=0 _use_color=false \
    numbers_mode=true bar_style="vertical" only_field="percent"
assert_eq "50" \
    "$(_format_entry)" \
    "_format_entry only percent with numbers"

_period="rolling" _percent=50 _duration_text="" \
    _short_mode=false one_line=true width=0 _use_color=true \
    numbers_mode=false bar_style="vertical" only_field="percent"
assert_eq "$(printf '\033[38;5;27m 50%%\033[39m')" \
    "$(_format_entry)" \
    "_format_entry only percent one-line color aligned"

_period="rolling" _percent=50 _duration_text="12345" \
    _short_mode=false one_line=false width=0 _use_color=false \
    numbers_mode=false bar_style="vertical" only_field="datetime"
assert_eq "12345" \
    "$(_format_entry)" \
    "_format_entry only datetime"

_period="rolling" _percent=50 _duration_text="12345" \
    _short_mode=false one_line=true width=0 _use_color=true \
    numbers_mode=false bar_style="vertical" only_field="datetime"
assert_eq "$(printf '\033[38;5;27m 12345\033[39m')" \
    "$(_format_entry)" \
    "_format_entry only datetime one-line color aligned"

# _parse_args: --force / -f sets force=true; default is false.
_parse_args
# shellcheck disable=SC2154  # force is set by _parse_args
assert_eq "false" "$force" "_parse_args default force is false"

_parse_args --force
assert_eq "true" "$force" "_parse_args --force sets force=true"

_parse_args -f
assert_eq "true" "$force" "_parse_args -f sets force=true"

# _parse_args: --only-* options can be combined with --short and --one-line.
display=""
only_field=""
only_period=""
one_line=""
date_mode=""
_parse_args --only-bar --short
assert_eq "bar" "$only_field" "_parse_args --only-bar --short accepted"
assert_eq "short" "$display" "_parse_args --only-bar --short mode"

_parse_args --only-bar --one-line
assert_eq "bar" "$only_field" "_parse_args --only-bar --one-line accepted"
assert_eq "true" "$one_line" "_parse_args --only-bar --one-line one_line"

_parse_args --only-percent --short
assert_eq "percent" "$only_field" "_parse_args --only-percent --short accepted"

_parse_args --only-datetime --one-line
assert_eq "datetime" "$only_field" "_parse_args --only-datetime --one-line accepted"

_parse_args --only-bar --date
assert_eq "bar" "$only_field" "_parse_args --only-bar --date accepted"
assert_eq "true" "$date_mode" "_parse_args --only-bar --date date_mode"

# _parse_args: --only-* period options.
_parse_args --only-rolling
assert_eq "rolling" "$only_period" "_parse_args --only-rolling accepted"

_parse_args --only-weekly
assert_eq "weekly" "$only_period" "_parse_args --only-weekly accepted"

_parse_args --only-monthly
assert_eq "monthly" "$only_period" "_parse_args --only-monthly accepted"

# _parse_args: period options can combine with --only-* output options.
_parse_args --only-weekly --only-percent
assert_eq "weekly" "$only_period" "_parse_args --only-weekly --only-percent period"
assert_eq "percent" "$only_field" "_parse_args --only-weekly --only-percent mode"

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
assert_args_fail "_parse_args rejects --only-rolling --only-weekly" --only-rolling --only-weekly
assert_args_fail "_parse_args rejects --only-weekly --only-monthly" --only-weekly --only-monthly
assert_args_fail "_parse_args rejects removed -r option" -r
assert_args_fail "_parse_args rejects removed --percent option" --percent
assert_args_fail "_main rejects --only-bar --short" --only-bar --short
assert_args_fail "_main rejects --only-bar --one-line" --only-bar --one-line

# _render_output helpers set the shared-state globals before each call.
# shellcheck disable=SC2034  # these globals are consumed by _render_output
_setup_render_output() {
    display="$1"
    color_mode="$2"
    width="$3"
    one_line="$4"
    date_mode="$5"
    numbers_mode="$6"
    bar_style="$7"
    only_field="$8"
    only_period="$9"
}

# _render_output: date prefix in one-line mode includes a comma.
# Save originals before overriding with stubs.
_timestamp_orig=$(declare -f _timestamp)
_human_readable_short_orig=$(declare -f _human_readable_short)
_seconds_until_iso_orig=$(declare -f _seconds_until_iso)
_human_readable_orig=$(declare -f _human_readable)
# shellcheck disable=SC2329  # invoked indirectly through _render_output
_timestamp() { printf '%s' "2026-08-23T12:00:00"; }
# shellcheck disable=SC2329  # invoked indirectly through _render_output
_human_readable_short() { printf '%s' "FIXED"; }
_setup_render_output "full" "plain" "0" "true" "true" "false" "vertical" "none" "all"
output=$(printf 'rolling,21,2026-08-23T15:00:00Z\nweekly,55,2026-08-23T14:00:00Z\n' \
    | _render_output)
assert_eq "2026-08-23T12:00:00,  21%  FIXED,  55%  FIXED" "$output" \
    "_render_output one-line date prefix uses comma"

# _render_output: -d with -n uses epoch seconds for the timestamp prefix.
# shellcheck disable=SC2329  # invoked indirectly through _render_output
_seconds_until_iso() { printf '%s' "SECS"; }
# shellcheck disable=SC2329  # invoked indirectly through _render_output
_timestamp() { printf '%s' "1755950400"; }
_setup_render_output "full" "plain" "0" "false" "true" "true" "vertical" "none" "all"
output=$(printf 'rolling,21,2026-08-23T15:00:00Z\nweekly,55,2026-08-23T14:00:00Z\n' \
    | _render_output)
first_line="${output%%$'\n'*}"
assert_eq "1755950400 rolling 21 SECS" "$first_line" \
    "_render_output numbers date prefix uses epoch seconds"

# _render_output: -d -n -1 uses epoch seconds and a comma separator.
_setup_render_output "full" "plain" "0" "true" "true" "true" "vertical" "none" "all"
output=$(printf 'rolling,21,2026-08-23T15:00:00Z\nweekly,55,2026-08-23T14:00:00Z\n' \
    | _render_output)
assert_eq "1755950400,  21   SECS,  55   SECS" "$output" \
    "_render_output numbers one-line date prefix uses epoch seconds and comma"

# _render_output: --only-period filters to a single period.
# shellcheck disable=SC2329  # invoked indirectly through _render_output
_human_readable() { printf '%s' "DURATION"; }
_setup_render_output "full" "plain" "0" "false" "false" "false" "vertical" "none" "weekly"
output=$(printf 'rolling,21,2026-08-23T15:00:00Z\nweekly,55,2026-08-23T14:00:00Z\nmonthly,45,2026-08-23T13:00:00Z\n' \
    | _render_output)
assert_eq " weekly 55% DURATION" "$output" \
    "_render_output --only-weekly filters periods"

# Restore the real functions.
unset -f _timestamp _human_readable_short _seconds_until_iso _human_readable
eval "$_timestamp_orig"
eval "$_human_readable_short_orig"
eval "$_seconds_until_iso_orig"
eval "$_human_readable_orig"

echo ""
echo "passed: $pass  failed: $fail"
exit "$fail"
