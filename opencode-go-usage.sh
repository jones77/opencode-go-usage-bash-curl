#!/usr/bin/env bash
# Print OpenCode Go usage numbers from
#   http://opencode.ai/workspace/wrk_workspace_id/go
# Expects a .env file with OPENCODE_GO_API_KEY=key in it.
set -euo pipefail

readonly progname="$(basename "${BASH_SOURCE[0]}")"
readonly progdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$progdir" || exit 1

readonly cache_filename=".opencode-go-usage-cache"
readonly cache_filename_ttl=120

exit_fail() {
    echo "$progname: error: $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $progname [options]

Print OpenCode Go usage numbers and reset times.

Options:
  -h, --help      show this help
  -c, --color     force colored output
  -p, --plain     force plain output (no color)
  -s, --short     compact output: <percent> <short-date>
  -1, --one-line  print all values on one line, comma-separated
  -w N, --width=N bar width, 0-13 (default: 8, 0 for -s/-1)

By default, color is used only when stdout is a terminal.
--one-line joins the three period lines with ", ".
-s and -1 default to --width=0 (no bar); add -wN to show one.

The progress bar shows -wN cells.  Each cell has 8 steps:

    ⎼▁▂▃▄▅▆▇█
    012345678

Use --width=N (0-13) to change the width; 0 suppresses the bar.

  Width  One step    One cell  50% bar
     13   0.9615%     7.6923%  $(_bar 50 13)
     12   1.0417%     8.3333%  $(_bar 50 12)
     11   1.1364%     9.0909%  $(_bar 50 11)
     10   1.25%       10%      $(_bar 50 10)
      9   1.3889%     11.1111% $(_bar 50 9)
      8   1.5625%     12.5%    $(_bar 50 8)
      7   1.7857%     14.2857% $(_bar 50 7)
      6   2.0833%     16.6667% $(_bar 50 6)
      5   2.5%        20%      $(_bar 50 5)
      4   3.125%      25%      $(_bar 50 4)
      3   4.1667%     33.3333% $(_bar 50 3)
      2   6.25%       50%      $(_bar 50 2)
      1  12.5%       100%      $(_bar 50 1)
EOF
}

_date() {
    # use gdate if it exists
    if gdate >/dev/null 2>&1
    then
        # FIXME: I don't think this worked on Mac when I tried it.
        gdate "$@"
    else
        date "$@"
    fi
}

_cache_file() {
    local local_cache="$progdir/$cache_filename"
    if touch "$local_cache.$$" 2>/dev/null
    then
        rm -f "$local_cache.$$"
        printf '%s' "$local_cache"
    else
        printf '%s' "${TMPDIR:-/tmp}/$cache_filename"
    fi
}

_mtime_seconds() {
    local file="$1"
    stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null
}

# shellcheck disable=SC2154  # associative-array keys, not variables
readonly -A period_color=(
    [rolling]=27
    [weekly]=28
    [monthly]=166
)

# shellcheck disable=SC2154  # associative-array keys, not variables
readonly -A period_label=(
    [rolling]="rolling"
    [weekly]="weekly"
    [monthly]="monthly"
)

format_duration() {
    declare -A args=(
        [d]=$1
        [h]=$2
        [m]=$3
        [s]=$4
    )
    string=
    for unit in "d" "h" "m" "s"
    do
        local value=${args[$unit]}
        (( value == 0 )) && continue

        if [[ -n "$string" ]]
        then
            string="$string "
        fi
        printf -v string "$string%2s$unit" "$value"
    done

    echo "$string"
}

_duration_from_iso8601() {
    local iso8601_date="$1"

    local target_seconds=$(_date -d "$iso8601_date" +%s)
    local now_seconds=$(_date +%s)
    local diff=$((target_seconds - now_seconds))

    (( diff < 0 )) && exit_fail "unexpected negative diff='$diff'"

    local days=$((    diff / 86400))
    local hours=$(((  diff % 86400) / 3600))
    local minutes=$(((diff % 3600)  / 60))
    local seconds=$(( diff % 60))

    echo "$days" "$hours" "$minutes" "$seconds"
}

human_readable() {
    local days hours minutes seconds
    read -r days hours minutes seconds <<< "$(_duration_from_iso8601 "$1")"

    format_duration "$days" "$hours" "$minutes" "$seconds"
}

human_readable_short() {
    local days hours minutes seconds
    read -r days hours minutes seconds <<< "$(_duration_from_iso8601 "$1")"

    local parts=()
    (( days > 0 ))    && parts+=("${days}d")
    (( hours > 0 ))   && parts+=("${hours}h")
    (( minutes > 0 )) && parts+=("${minutes}m")
    (( seconds > 0 )) && parts+=("${seconds}s")

    if (( ${#parts[@]} == 0 ))
    then
        echo "0s"
    elif (( ${#parts[@]} == 1 ))
    then
        echo "${parts[0]}"
    else
        echo "${parts[0]}${parts[1]}"
    fi
}

_bar() {
    local percent="$1"
    local width="$2"

    # Total eighth-steps, split into full cells + the partial step.
    # Integer division truncates down so we never show a step we haven't reached.
    local total=$(( percent * width * 8 / 100 ))
    local int=$((   total / 8 ))
    local steps=$(( total % 8 ))

    if (( int > width )) # Clamp in case the API ever returns >100%.
    then
        int=$width
    fi

    local empty="⎼"
    local last=""
    local remaining=$(( width - int ))
    if (( remaining > 0 ))
    then
        case $steps in
            0) last="$empty" ;;
            1) last="▁" ;;
            2) last="▂" ;;
            3) last="▃" ;;
            4) last="▄" ;;
            5) last="▅" ;;
            6) last="▆" ;;
            7) last="▇" ;;
        esac
        remaining=$(( remaining - 1 ))
    fi

    local i
    for (( i = 0; i < int; i++ ))
    do
        printf "%s" "█"
    done
    printf "%s" "$last"
    for (( i = 0; i < remaining; i++ ))
    do
        printf "%s" "$empty"
    done
}

_parse_usage_json() {
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)["usage"]
    for period in ("rolling", "weekly", "monthly"):
        window = data[period]
        percent = int(float(window["percent"]))
        resets_at = window["resetsAt"]
        print(f"{period},{percent},{resets_at}")
except (json.JSONDecodeError, KeyError, ValueError, TypeError) as e:
    sys.exit(f"failed to parse API response: {e}")
'
}

read_cache() {
    local cache_file="$1"
    local period percent reset n=0 buf=""
    while IFS=, read -r period percent reset
    do
        [[ -n "$period" ]] || continue
        buf="$buf$period,$percent,$reset"$'\n'
        n=$((n + 1))
    done < "$cache_file"

    (( n != 3 )) && \
        exit_fail "expected cache_file='$cache_file' to have 3 lines in it"

    printf '%s' "$buf"
}

fetch_api() {
    local cache_file="$1"

    # need OPENCODE_GO_API_KEY to call the API, .env is in the .gitignore file
    # shellcheck source=/dev/null
    source .env \
        || exit_fail "expected to source ./.env to get \$OPENCODE_GO_API_KEY"
    if [ -z "$OPENCODE_GO_API_KEY" ]
    then
        echo "$progname: error: need a OPENCODE_GO_API_KEY environment variable." >&2
        exit 1
    fi

    readonly response=$(curl \
        -s -w "%{http_code}" -X GET "https://opencode.ai/zen/go/v1/usage" \
        -H "Authorization: Bearer $OPENCODE_GO_API_KEY" \
        -H "Accept: application/json"
    )

    readonly http_status="${response:${#response}-3}"
    readonly body="${response:0:${#response}-3}"

    (( http_status != 200 )) && exit_fail \
        "API request failed with status: $http_status
response: '$body'"

    local parsed
    parsed=$(_parse_usage_json <<< "$body") || exit_fail "failed to parse API response"

    local line_count
    line_count=$(printf '%s\n' "$parsed" | wc -l)
    (( line_count != 3 )) && \
        exit_fail "expected API response to contain 3 periods"

    local tmp="$cache_file.$$"
    # shellcheck disable=SC2015  # atomic write: only keep tmp if printf && mv both succeed
    printf '%s\n' "$parsed" > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$cache_file" 2>/dev/null \
        || rm -f "$tmp"

    printf '%s\n' "$parsed"
}

load_lines() {
    local cache_file
    cache_file=$(_cache_file)
    local now mtime=0
    now=$(_date +%s)

    if [[ -f "$cache_file" ]]
    then
        mtime=$(_mtime_seconds "$cache_file" 2>/dev/null) || mtime=0
        mtime=${mtime:-0}
    fi

    if (( now - mtime < cache_filename_ttl ))  # cache_filename TTL seconds
    then
        read_cache "$cache_file"
    else
        fetch_api "$cache_file"
    fi
}

_format_entry() {
    local period="$1" percent="$2" timedate="$3" short_mode="$4" one_line="$5" width="$6" use_color="$7"

    local short_period="${period_label[$period]}"
    [[ -n "$short_period" ]] || exit_fail "unexpected period: '$period'"

    local color_esc="" reset_esc=""
    if "$use_color"
    then
        color_esc=$(printf '\033[38;5;%sm' "${period_color[$period]}")
        reset_esc=$'\033[39m'
    fi

    local bar_part=""
    if (( width > 0 ))
    then
        bar_part=" $(_bar "$percent" "$width")"
    fi

    local duration
    if "$short_mode"
    then
        duration=$(human_readable_short "$timedate")
        printf "%s%2.0f%%%s %s%s" \
            "$color_esc" "$percent" "$bar_part" "$duration" "$reset_esc"
    elif "$one_line"
    then
        duration=$(human_readable_short "$timedate")
        printf "%s%.0f%%%s %s%s" \
            "$color_esc" "$percent" "$bar_part" "$duration" "$reset_esc"
    else
        duration=$(human_readable "$timedate")
        printf "%s%7s %2.0f%%%s %s%s" \
            "$color_esc" "$short_period" "$percent" "$bar_part" "$duration" "$reset_esc"
    fi
}

render_output() {
    local mode="$1" color_mode="$2" width="$3" one_line="$4"

    local use_color=false
    case "$color_mode" in
        color) use_color=true ;;
        plain) use_color=false ;;
        auto)  [ -t 1 ] && use_color=true ;;
    esac

    local short_mode=false
    [ "$mode" = "short" ] && short_mode=true

    local period percent timedate joined=""
    while IFS=, read -r period percent timedate
    do
        local line
        line=$(_format_entry "$period" "$percent" "$timedate" "$short_mode" "$one_line" "$width" "$use_color")
        if "$one_line"
        then
            joined="${joined:+$joined, }$line"
        else
            printf '%s\n' "$line"
        fi
    done

    if "$one_line" && [[ -n "$joined" ]]
    then
        printf '%s\n' "$joined"
    fi
}

main() {
    mode="full"
    color_mode="auto"
    width=""
    one_line=false

    while (( $# > 0 ))
    do
        case "$1" in
            --width=*) width="${1#--width=}" ;;
            --width)   exit_fail "--width requires a value (use --width=N)" ;;
            -w) (( $# < 2 )) && exit_fail "-w requires a value"  # eg -w 12
                width="$2"
                shift
                ;;
            -w*)          width="${1#-w}"      ;;  # eg -w12
            -s|--short)   mode="short"         ;;
            -1|--one-line) one_line=true        ;;
            -p|--plain)   color_mode="plain"   ;;
            -c|--color)   color_mode="color"   ;;
            -h|--help)    usage; exit 0         ;;
            *)
                usage
                exit_fail "unknown argument: '$1'"
                ;;
        esac
        shift
    done

    if [[ -z "$width" ]]  # Default width: 0 for compact views, 8 otherwise
    then
        if [ "$mode" = "short" ] || [ "$one_line" = true ]
        then
            width=0
        else
            width=8
        fi
    fi

    (( width < 0 || width > 13 )) && \
        exit_fail "width must be between 0 and 13 (got '$width')"

    [ "$mode" = "short" ] && [ "$one_line" = true ] && \
        exit_fail "--short and --one-line are mutually exclusive"

    # local mode="$1" color_mode="$2" width="$3" one_line="$4"
    load_lines | render_output "$mode" "$color_mode" "$width" "$one_line"
}

main "$@"
