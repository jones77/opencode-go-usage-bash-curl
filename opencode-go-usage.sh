#!/usr/bin/env bash
# Print OpenCode Go usage numbers from
#   http://opencode.ai/workspace/wrk_workspace_id/go
# Expects a .env file with OPENCODE_GO_API_KEY=key in it.
# Depends on python3.
set -euo pipefail

readonly progname="$(basename "${BASH_SOURCE[0]}")"
readonly progdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$progdir" || exit 1

readonly cache_filename=".opencode-go-usage-cache"
readonly cache_filename_ttl=120

_exit_fail() {
    echo "$progname: error: $*" >&2
    exit 1
}

_usage() {
    cat <<EOF
Usage: $progname [options]

Print OpenCode Go usage numbers and reset times.

Options:
  -h, --help       show this help
  -c, --color      force colored output
  -p, --plain      force plain output (no color)
  -d, --date       prefix each output line with a local ISO timestamp
  -n, --numbers    omit '%' and show seconds remaining instead of duration
  -1, --one-line   print all values on one line, comma-separated
  -s, --short      compact output: <percent> <short-date>
  --only-bar       show only the progress bar
  --only-percent   show only the percent value
  --only-datetime  show only the reset time / duration
  --only-rolling   show only the rolling period
  --only-weekly    show only the weekly period
  --only-monthly   show only the monthly period
  -g, --gradient   gradient shade bar style
  -v, --vertical   vertical bar style (default)
  -z, --horizontal horizontal bar style
  -w N, --width=N  bar width, 0-13 (default: 8; 0 when no bar is drawn)

By default, color is used only when stdout is a terminal.
  --date uses the local time (YYYY-MM-DDTHH:MM:SS).
  --only-bar, --only-percent, and --only-datetime are mutually exclusive
  with each other.
  --only-rolling, --only-weekly, and --only-monthly are mutually exclusive
  with each other.
Bar styles (-v/-z/-g) are mutually exclusive; -v is the default.

The -g, gradient bar uses four shades with 4 steps per cell:        ␣░▒▓█
                                                                    01234
The default vertical bar fills bottom-to-top with 8 steps per cell:  ␣▁▂▃▄▅▆▇█
                                                                    012345678
The -z, horizontal bar fills left-to-right with 8 steps per cell:   ␣▏▎▍▌▋▊▉█
                                                                    012345678
All include an empty cell: ␣

13 is the maximum width because OpenCode Go's API doesn't use decimals.

  Width  One step   One cell  50% -v/--vertical  50% -z/--horizontal
$(for ww in 13 12 11 10 9 8 7 6 5 4 3 2 1
  do
      case "$ww" in
          13) step="0.9615"; cell="7.6923" ;;
          12) step="1.0417"; cell="8.3333" ;;
          11) step="1.1364"; cell="9.0909" ;;
          10) step="1.25";   cell="10" ;;
          9)  step="1.3889"; cell="11.1111" ;;
          8)  step="1.5625"; cell="12.5" ;;
          7)  step="1.7857"; cell="14.2857" ;;
          6)  step="2.0833"; cell="16.6667" ;;
          5)  step="2.5";    cell="20" ;;
          4)  step="3.125";  cell="25" ;;
          3)  step="4.1667"; cell="33.3333" ;;
          2)  step="6.25";   cell="50" ;;
          1)  step="12.5";   cell="100" ;;
      esac
      vbar="$(_bar 50 "$ww" vertical)"
      hbar="$(_bar 50 "$ww" horizontal)"
      # printf field widths count bytes, but the bar glyphs are 3-byte UTF-8
      # characters, so pad manually to a 17-character field.
      printf '  %5d  %7.4f%% %9.4f%%  %s%*s  %s%*s\n' \
                "$ww" "$step" "$cell" \
                "$vbar" $((17 - ww)) '' \
                "$hbar" $((17 - ww)) ''
  done)

At width 13 one step is 1.92%; rendering uses integer math, so the
recurring decimal only appears in this description.
EOF
}

_timestamp() {
    local numbers_mode="$1"
    if "$numbers_mode"
    then
        printf '%s' "$(date +%s)"
    else
        printf '%s' "$(date +%Y-%m-%dT%H:%M:%S)"
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

# Option metadata used by _parse_args. getopts consumes the optstring; the
# long_alias map lets the long-option loop dispatch through _apply_option.
readonly _optstring=":hcpdn1svzgw:"

# shellcheck disable=SC2154  # associative-array keys, not variables
readonly -A _long_alias=(
    [color]=c
    [date]=d
    [gradient]=g
    [help]=h
    [horizontal]=z
    [numbers]=n
    [one-line]=1
    [plain]=p
    [short]=s
    [vertical]=v
    [width]=w
)

_format_duration() {
    declare -A args=(
        [d]=$1
        [h]=$2
        [m]=$3
        [s]=$4
    )
    local string=
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

# Portable ISO-8601 -> seconds-until-target.  Uses python3 so we don't
# depend on GNU date -d.  Naive strings are interpreted as UTC.
_seconds_until_iso() {
    python3 -c '
import sys, datetime
s = sys.argv[1]
if s.endswith("Z"):
    s = s[:-1] + "+00:00"
try:
    dt = datetime.datetime.fromisoformat(s)
except ValueError as e:
    sys.exit(f"failed to parse ISO timestamp {s!r}: {e}")
if dt.tzinfo is None:
    dt = dt.replace(tzinfo=datetime.timezone.utc)
now = datetime.datetime.now(datetime.timezone.utc)
print(int((dt - now).total_seconds()))
' "$1"
}

_duration_from_iso8601() {
    local iso8601_date="$1"

    local diff
    diff=$(_seconds_until_iso "$iso8601_date")

    (( diff < 0 )) && _exit_fail "unexpected negative diff='$diff'"

    local days=$((    diff / 86400))
    local hours=$(((  diff % 86400) / 3600))
    local minutes=$(((diff % 3600)  / 60))
    local seconds=$(( diff % 60))

    echo "$days" "$hours" "$minutes" "$seconds"
}

_human_readable() {
    local days hours minutes seconds
    read -r days hours minutes seconds <<< "$(_duration_from_iso8601 "$1")"

    _format_duration "$days" "$hours" "$minutes" "$seconds"
}

_human_readable_short() {
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
    local style="${3:-vertical}"

    local steps_per_cell empty full
    local -a partial
    empty="␣"
    full="█"
    case "$style" in
          gradient) steps_per_cell=4; partial=(░ ▒ ▓) ;;
        horizontal) steps_per_cell=8; partial=(▏ ▎ ▍ ▌ ▋ ▊ ▉) ;;
          vertical) steps_per_cell=8; partial=(▁ ▂ ▃ ▄ ▅ ▆ ▇) ;;
                 *) _exit_fail "unknown bar style: '$style'" ;;
    esac

    # Total sub-steps, split into full cells + the partial step.
    # Integer division truncates down so we never show a step we haven't reached.
    local total=$(( percent * width * steps_per_cell / 100 ))
    local int=$((   total / steps_per_cell ))
    local steps=$(( total % steps_per_cell ))

    if (( int > width )) # Clamp in case the API ever returns >100%.
    then
        int=$width
    fi

    local last=""
    local remaining=$(( width - int ))
    if (( remaining > 0 ))
    then
        if (( steps == 0 ))
        then
            last="$empty"
        else
            last="${partial[$((steps - 1))]}"
        fi
        remaining=$(( remaining - 1 ))
    fi

    local i
    for (( i = 0; i < int; i++ ))
    do
        printf "%s" "$full"
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

_read_cache() {
    local cache_file="$1"
    local period percent reset n=0 buf=""
    while IFS=, read -r period percent reset
    do
        [[ -n "$period" ]] || continue
        buf="$buf$period,$percent,$reset"$'\n'
        n=$((n + 1))
    done < "$cache_file"

    (( n != 3 )) && \
        _exit_fail "expected cache_file='$cache_file' to have 3 lines in it"

    printf '%s' "$buf"
}

_fetch_api() {
    local cache_file="$1"

    # need OPENCODE_GO_API_KEY to call the API, .env is in the .gitignore file
    # shellcheck source=/dev/null
    source .env \
        || _exit_fail "expected to source ./.env to get \$OPENCODE_GO_API_KEY"
    if [ -z "$OPENCODE_GO_API_KEY" ]
    then
        echo "$progname: error: need a OPENCODE_GO_API_KEY environment variable." >&2
        exit 1
    fi

    # Keep the bearer token out of curl's argv (visible via ps) by reading the
    # Authorization header from a short-lived, restricted temp file.
    local auth_header_file
    auth_header_file=$(mktemp "${TMPDIR:-/tmp}/opencode-go-usage-auth.XXXXXX")
    # shellcheck disable=SC2064  # $auth_header_file expanded here intentionally
    trap "rm -f '$auth_header_file'" EXIT
    (umask 077; printf 'Authorization: Bearer %s\n' "$OPENCODE_GO_API_KEY" > "$auth_header_file")

    readonly response=$(curl \
        -s -w "%{http_code}" -X GET "https://opencode.ai/zen/go/v1/usage" \
        -H "@$auth_header_file" \
        -H "Accept: application/json"
    )

    trap - EXIT
    rm -f "$auth_header_file"

    readonly http_status="${response:${#response}-3}"
    readonly body="${response:0:${#response}-3}"

    (( http_status != 200 )) && _exit_fail \
        "API request failed with status: $http_status
response: '$body'"

    local parsed
    parsed=$(_parse_usage_json <<< "$body") || _exit_fail "failed to parse API response"

    local line_count
    line_count=$(printf '%s\n' "$parsed" | wc -l)
    (( line_count != 3 )) && \
        _exit_fail "expected API response to contain 3 periods"

    local tmp="$cache_file.$$"
    # shellcheck disable=SC2015  # atomic write: only keep tmp if printf && mv both succeed
    printf '%s\n' "$parsed" > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$cache_file" 2>/dev/null \
        || rm -f "$tmp"

    printf '%s\n' "$parsed"
}

_load_lines() {
    local cache_file
    cache_file=$(_cache_file)
    local now mtime=0
    now=$(date +%s)

    if [[ -f "$cache_file" ]]
    then
        mtime=$(_mtime_seconds "$cache_file" 2>/dev/null) || mtime=0
        mtime=${mtime:-0}
    fi

    if (( now - mtime < cache_filename_ttl ))  # cache_filename TTL seconds
    then
        _read_cache "$cache_file"
    else
        _fetch_api "$cache_file"
    fi
}

_format_entry() {
    local period="$1" percent="$2" duration_text="$3" short_mode="$4" \
        one_line="$5" width="$6" use_color="$7" numbers_mode="$8" \
        bar_style="${9}" only_mode="${10}"

    local short_period="${period_label[$period]}"
    [[ -n "$short_period" ]] || _exit_fail "unexpected period: '$period'"

    local color_esc="" reset_esc=""
    if "$use_color"
    then
        color_esc=$(printf '\033[38;5;%sm' "${period_color[$period]}")
        reset_esc=$'\033[39m'
    fi

    local bar_part=""
    if (( width > 0 ))
    then
        bar_part=" $(_bar "$percent" "$width" "$bar_style")"
    fi

    case "$only_mode" in
        bar)
            printf "%s%s%s" \
                "$color_esc" "$(_bar "$percent" "$width" "$bar_style")" "$reset_esc"
            return
            ;;
        percent)
            local pfmt="%.0f"
            if "$one_line" && "$use_color"
            then
                pfmt="%3.0f"
            fi
            # Use "%%" so printf prints a literal "%"; a bare "%" would be
            # interpreted as the start of another conversion specifier.
            local suffix="%%"
            if "$numbers_mode"
            then
                suffix=""
            fi
            printf "%s${pfmt}${suffix}%s" \
                "$color_esc" "$percent" "$reset_esc"
            return
            ;;
        datetime)
            local dfmt="%s"
            if "$one_line" && "$use_color"
            then
                dfmt="%6s"
            fi
            printf "%s${dfmt}%s" "$color_esc" "$duration_text" "$reset_esc"
            return
            ;;
    esac

    local prefix="" pfmt="%.0f" dfmt="%s"
    if "$short_mode"
    then
        pfmt="%2.0f"
        dfmt="%7s"
    elif "$one_line"
    then
        if "$use_color"
        then
            pfmt="%3.0f"
            dfmt="%6s"
        fi
    else
        prefix=$(printf '%7s ' "$short_period")
        pfmt="%2.0f"
    fi

    # Use "%%" so printf prints a literal "%"; a bare "%" would be
    # interpreted as the start of another conversion specifier.
    local suffix="%%"
    if "$numbers_mode"
    then
        suffix=""
    fi

    # shellcheck disable=SC2059
    # pfmt/dfmt/suffix are controlled format fragments, not user input.
    printf "%s%s${pfmt}${suffix}%s ${dfmt}%s" \
        "$color_esc" "$prefix" "$percent" "$bar_part" "$duration_text" "$reset_esc"
}

_render_output() {
    # Reads and renders the "period,percent,resetsAt" CSV lines from stdin.
    # Uses the shared state globals documented above _parse_args.

    local use_color=false
    case "$color_mode" in
        color) use_color=true ;;
        plain) use_color=false ;;
        auto)  [ -t 1 ] && use_color=true ;;
    esac

    local short_mode=false
    [ "$mode" = "short" ] && short_mode=true

    local timestamp=""
    if "$date_mode"
    then
        if "$one_line"
        then
            timestamp="$(_timestamp "$numbers_mode"), "
        else
            timestamp="$(_timestamp "$numbers_mode") "
        fi
    fi

    local bar_width=$width
    if [ "$only_mode" = "percent" ] || [ "$only_mode" = "datetime" ]
    then
        bar_width=0
    fi

    local period percent timedate joined=""
    while IFS=, read -r period percent timedate
    do
        if [[ "$only_period" != "all" && "$period" != "$only_period" ]]
        then
            continue
        fi

        local duration_text
        if [ "$only_mode" = "bar" ] || [ "$only_mode" = "percent" ]
        then
            duration_text=""
        elif "$numbers_mode"
        then
            duration_text=$(_seconds_until_iso "$timedate")
        elif "$short_mode" || "$one_line"
        then
            duration_text=$(_human_readable_short "$timedate")
        else
            duration_text=$(_human_readable "$timedate")
        fi

        local line
        line=$(_format_entry "$period" "$percent" "$duration_text" \
            "$short_mode" "$one_line" "$bar_width" "$use_color" \
            "$numbers_mode" "$bar_style" "$only_mode")
        if "$one_line"
        then
            joined="${joined:+$joined, }$line"
        else
            printf '%s\n' "${timestamp}${line}"
        fi
    done

    if "$one_line" && [[ -n "$joined" ]]
    then
        printf '%s\n' "${timestamp}${joined}"
    fi
}

_apply_option() {
    local short="$1" arg="${2:-}"
    case "$short" in
        h) _usage; exit 0 ;;
        c) color_mode="color" ;;
        p) color_mode="plain" ;;
        d) date_mode=true ;;
        n) numbers_mode=true ;;
        1) one_line=true ;;
        s) mode="short" ;;
        v|z|g)
            if [[ "$bar_style_set" == true ]]
            then
                _exit_fail "bar styles are mutually exclusive"
            fi
            case "$short" in
                v) bar_style="vertical" ;;
                z) bar_style="horizontal" ;;
                g) bar_style="gradient" ;;
            esac
            bar_style_set=true
            ;;
        w) width="$arg" ;;
        *) _exit_fail "unknown option: -$short" ;;
    esac
}

_set_only_mode() {
    local new="$1"
    if [[ "$only_mode" != "none" ]]
    then
        _exit_fail "--only-* options are mutually exclusive"
    fi
    only_mode="$new"
}

_set_only_period() {
    local new="$1"
    if [[ "$only_period" != "all" ]]
    then
        _exit_fail "--only-rolling/--only-weekly/--only-monthly are mutually exclusive"
    fi
    only_period="$new"
}

# Shared state: the following globals are set by _parse_args and consumed by
# _main and _render_output. Keep them in sync across these functions.
#
#   mode          "full" | "short"
#   color_mode    "auto" | "color" | "plain"
#   width         bar width (numeric string), "" means "use default"
#   one_line      true | false
#   date_mode     true | false
#   numbers_mode  true | false
#   bar_style     "vertical" | "horizontal" | "gradient"
#   bar_style_set true | false (used only during _parse_args for exclusivity)
#   only_mode     "none" | "bar" | "percent" | "datetime"
#   only_period   "all" | "rolling" | "weekly" | "monthly"
#
# _main uses: mode, one_line, only_mode, width (for default-width logic).
# _render_output uses all of the above except bar_style_set.
_parse_args() {
    mode="full"
    color_mode="auto"
    width=""
    one_line=false
    date_mode=false
    numbers_mode=false
    bar_style="vertical"
    bar_style_set=false
    only_mode="none"
    only_period="all"

    # Separate short and long options before dispatching. Only -w/--width
    # take values, so those two forms must consume their following argument.
    local -a short_args=()
    local -a long_args=()
    while (( $# > 0 ))
    do
        case "$1" in
            --width)
                (( $# < 2 )) && _exit_fail "--width requires a value"
                long_args+=("$1" "$2")
                shift 2
                ;;
            --width=*|--*)
                long_args+=("$1")
                shift
                ;;
            -w)
                if (( $# < 2 ))
                then
                    _exit_fail "-w requires a value"
                fi
                short_args+=("$1" "$2")
                shift 2
                ;;
            -*)
                if [[ "$1" == "-" ]]
                then
                    _usage
                    _exit_fail "unknown argument: '-'"
                fi
                short_args+=("$1")
                shift
                ;;
            *)
                _usage
                _exit_fail "unknown argument: '$1'"
                ;;
        esac
    done

    local OPTIND=1 OPTARG="" opt
    while getopts "$_optstring" opt "${short_args[@]}"
    do
        case "$opt" in
            \?) _exit_fail "unknown option: -$OPTARG" ;;
             :) _exit_fail "-$OPTARG requires a value" ;;
             *) if [[ "$opt" == "w" ]]
                then
                    _apply_option "$opt" "$OPTARG"
                else
                    _apply_option "$opt"
                fi
             ;;
        esac
    done

    set -- "${long_args[@]}"
    while (( $# > 0 ))
    do
        local arg="$1"
        shift
        case "$arg" in
            --width=*) width="${arg#--width=}" ;;
            --width)
                if (( $# == 0 ))
                then
                    _exit_fail "--width requires a value"
                fi
                _apply_option "w" "$1"
                shift
                ;;
            --only-bar)      _set_only_mode "bar"       ;;
            --only-percent)  _set_only_mode "percent"   ;;
            --only-datetime) _set_only_mode "datetime"  ;;
            --only-rolling)  _set_only_period "rolling" ;;
            --only-weekly)   _set_only_period "weekly"  ;;
            --only-monthly)  _set_only_period "monthly" ;;
            --*)
                local name="${arg#--}"
                local short
                short="${_long_alias[$name]:-}"
                if [[ -z "$short" ]]
                then
                    _usage
                    _exit_fail "unknown argument: '$arg'"
                fi
                if [[ "$short" == "w" ]]
                then
                    (( $# == 0 )) && _exit_fail "--$name requires a value"
                    _apply_option "$short" "$1"
                    shift
                else
                    _apply_option "$short"
                fi
                ;;
        esac
    done
}

_main() {
    _parse_args "$@"

    if [[ -z "$width" ]]  # Default width: 0 for compact views, 8 otherwise
    then
        if [ "$mode" = "short" ] || [ "$one_line" = true ] || \
           [ "$only_mode" = "percent" ] || [ "$only_mode" = "datetime" ]
        then
            width=0
        else
            width=8
        fi
    fi

    [[ "$width" =~ ^[0-9]+$ ]] || \
        _exit_fail "width must be a number (got '$width')"

    (( width < 0 || width > 13 )) && \
        _exit_fail "width must be between 0 and 13 (got '$width')"

    [ "$mode" = "short" ] && [ "$one_line" = true ] && \
        _exit_fail "--short and --one-line are mutually exclusive"

    _load_lines | _render_output
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
    _main "$@"
fi
