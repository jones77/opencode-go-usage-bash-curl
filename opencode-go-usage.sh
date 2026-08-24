#!/usr/bin/env bash
# Print OpenCode Go usage numbers.
# Expects a .env file with OPENCODE_GO_API_KEY=key in it.
# Depends on python3.
set -euo pipefail

readonly progname="$(basename "${BASH_SOURCE[0]}")"
readonly progdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly cache_filename=".opencode-go-usage-cache"
readonly cache_filename_ttl=120

exit_fail() {
    echo "$progname: error: $*" >&2
    exit 1
}

usage() {
    local use_color=false
    [[ -t 1 ]] && use_color=true

    local rolling="rolling" weekly="weekly" monthly="monthly"
    local slash="/"
    if "$use_color"
    then
        local rc="${period_color[rolling]}" wc="${period_color[weekly]}" mc="${period_color[monthly]}"
        rolling=$'\033[38;5;'"${rc}"$'m'"rolling"$'\033[39m'
        weekly=$'\033[38;5;'"${wc}"$'m'"weekly"$'\033[39m'
        monthly=$'\033[38;5;'"${mc}"$'m'"monthly"$'\033[39m'
    fi

    cat <<EOF
Usage: $progname [options]

Print OpenCode Go usage numbers and reset times.

Options:
  -h, --help
  -c, --color    force colored output (default when a terminal detected)
  -p, --plain    force plain output (no color)
  -d, --date     prefix each output line with a local ISO timestamp
  -f, --force    bypass the cache; always fetch from the API (and refresh the cache)
  -n, --numbers  omit '%' and show seconds remaining instead of duration
  -1, --one-line print all values on one line, comma-separated
  -s, --short    compact output: <percent> <short-date>
Bar styles (-v/-z/-g) are mutually exclusive; -v is the default, ␣ means empty
  -v,   --vertical   vertical bar style
  -z,   --horizontal horizontal bar style
  -g,   --gradient   gradient shade bar style
  -w N, --width=N    0-13 (8 is the default; 0 means no bar is drawn)
        --only-percent/-bar/-datetime
            only show one field: percent remaining / progress bar /  reset time
        --only-${rolling}${slash}-${weekly}${slash}-${monthly}
           only show one period: ${rolling}${slash}${weekly}${slash}${monthly}

All styles use an empty cell, ␣.  The gradient bar uses four shades: ␣░▒▓█
The default vertical bar fills bottom-to-top with 8 steps per cell:  ␣▁▂▃▄▅▆▇█
The -z, horizontal bar fills left-to-right with 8 steps per cell:    ␣▏▎▍▌▋▊▉█

  Width  One step   One cell  67% -v/--vertical  67% -z/--horizontal
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
      vbar="$(bar 67 "$ww" vertical)"
      hbar="$(bar 50 "$ww" horizontal)"
      # printf field widths count bytes, but the bar glyphs are 3-byte UTF-8
      # characters, so pad manually to a 17-character field.
      printf '  %5d  %7.4f%% %9.4f%%  %s%*s  %s%*s\n' \
                "$ww" "$step" "$cell" \
                "$vbar" $((17 - ww)) '' \
                "$hbar" $((17 - ww)) ''
  done)
EOF
}

timestamp() {
    local numbers_mode="$1"
    if "$numbers_mode"
    then
        printf '%s' "$(date +%s)"
    else
        printf '%s' "$(date +%Y-%m-%dT%H:%M:%S)"
    fi
}

cache_file() {
    local local_cache="$progdir/$cache_filename"
    if touch "$local_cache.$$" 2>/dev/null
    then
        rm -f "$local_cache.$$"
        printf '%s' "$local_cache"
    else
        printf '%s' "${TMPDIR:-/tmp}/$cache_filename"
    fi
}

mtime_seconds() {
    local file="$1"
    stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null
}

readonly -A period_color=([rolling]=27 [weekly]=28 [monthly]=166)

format_duration() {
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

    echo "${string:-0s}"
}

# Portable ISO-8601 -> seconds-until-target.  Uses python3 so we don't
# depend on GNU date -d.  Naive strings are interpreted as UTC.
seconds_until_iso() {
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

duration_from_iso8601() {
    local iso8601_date="$1"
    local diff
    diff=$(seconds_until_iso "$iso8601_date") \
        || exit_fail "failed to parse ISO timestamp: $iso8601_date"
    (( diff < 0 )) && diff=0

    local days=$((    diff / 86400))
    local hours=$(((  diff % 86400) / 3600))
    local minutes=$(((diff % 3600)  / 60))
    local seconds=$(( diff % 60))

    echo "$days" "$hours" "$minutes" "$seconds"
}

human_readable() {
    local   days hours minutes seconds
    read -r days hours minutes seconds <<< "$(duration_from_iso8601 "$1")"
    format_duration "$days" "$hours" "$minutes" "$seconds"
}

human_readable_short() {
    local   days hours minutes seconds
    read -r days hours minutes seconds <<< "$(duration_from_iso8601 "$1")"

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

bar() {
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
                 *) exit_fail "unknown bar style: '$style'" ;;
    esac

    # Total sub-steps, split into full cells + the partial step.
    # Integer division truncates down, we never show a step we haven't reached.
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

parse_usage_json() {
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

    # Save the current options and temporarily disable tracing
    # to keep the bearer token out of debug output.
    local saved_opts="$-"
    set +x +v

    # shellcheck disable=SC1091 # associative-array keys, not variables
    source "$progdir/.env" \
        || exit_fail "expected to source ./.env to get OPENCODE_GO_API_KEY"
    [[ -n "${OPENCODE_GO_API_KEY:-}" ]] \
        || exit_fail ".env must define OPENCODE_GO_API_KEY"
    local curl_exit=0 response
    # Using `printf | curl` to prevent ps from seeing the API_KEY.
    response=$(printf 'Authorization: Bearer %s\n' "$OPENCODE_GO_API_KEY" \
        | curl  -s -w "%{http_code}" --connect-timeout 10 --max-time 30 \
                -X GET "https://opencode.ai/zen/go/v1/usage" \
                -H @- -H "Accept: application/json"
    ) || curl_exit=$?

    # Restore the original tracing options.
    [[ "$saved_opts" == *x* ]] && set -x
    [[ "$saved_opts" == *v* ]] && set -v

    (( curl_exit != 0 )) && exit_fail \
        "curl failed with exit code $curl_exit (connection error)"

    local -r http_status="${response:${#response}-3}"
    local -r body="${response:0:${#response}-3}"

    (( http_status != 200 )) && exit_fail \
        "API request failed with status: $http_status
response: '$body'"

    local parsed
    parsed=$(parse_usage_json <<< "$body") \
        || exit_fail "failed to parse API response"

    local line_count
    line_count=$(printf '%s\n' "$parsed" | wc -l)
    (( line_count != 3 )) && \
        exit_fail "expected API response to contain 3 periods"

    local tmp="$cache_file.$$"
    if printf '%s\n' "$parsed" > "$tmp" 2>/dev/null
    then
        mv -f "$tmp" "$cache_file" 2>/dev/null
    else
        rm -f "$tmp"
    fi

    printf '%s\n' "$parsed"
}

# Option metadata used by parse_args. getopts consumes _optstring;
# the long_alias map lets the long-option loop dispatch through apply_option.
readonly _optstring=":hcpdn1svzgw:f"

# shellcheck disable=SC2154  # associative-array keys, not variables
readonly -A _long_alias=(
    [color]=c
    [date]=d
    [force]=f
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

# Shared state: The following globals are set by: parse_args, apply_option
#               and consumed by: main, render_output, format_entry
#
# Keep them in sync across these functions!
#
#       bar_style      "vertical" | "horizontal" | "gradient"
#       bar_style_set  true | false
#       color_mode     "auto" | "color" | "plain"
#       date_mode      true | false
#       display        "full" | "short"
#       force          true | false
#       numbers_mode   true | false
#       one_line       true | false
#       only_period    "all" | "rolling" | "weekly" | "monthly"
#       only_field     "none" | "bar" | "percent" | "datetime"
#       width          bar width (numeric string), "" means "use default"
#
# Additional shared state set by render_output and consumed by format_entry:
#
#       _duration      formatted reset-time string
#       _percent       current period percent (integer)
#       _period        current period name ("rolling", "weekly", "monthly")
#       _short_mode    true | false (derived from display)
#       _use_color     true | false (derived from color_mode)
bar_style="vertical"
bar_style_set=false
color_mode="auto"
date_mode=false
display="full"
force=false
numbers_mode=false
one_line=false
only_period="all"
only_field="none"
width=""

_duration=""
_percent=""
_period=""
_short_mode=false
_use_color=false

format_entry() {
    local short_period="$_period"
    [[ -n "$short_period" ]] || exit_fail "unexpected period: '$_period'"

    local color_esc="" reset_esc=""
    if "$_use_color"
    then
        color_esc=$(printf '\033[38;5;%sm' "${period_color[$_period]}")
        reset_esc=$'\033[39m'
    fi

    case "$only_field" in
        bar)
            printf "%s%s%s" \
                "$color_esc" \
                "$(bar "$_percent" "$width" "$bar_style")" "$reset_esc"
            return
            ;;
        percent)
            local pfmt="%.0f"
            if "$one_line" && "$_use_color"
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
                "$color_esc" "$_percent" "$reset_esc"
            return
            ;;
        datetime)
            local dfmt="%s"
            if "$one_line" && "$_use_color"
            then
                dfmt="%6s"
            fi
            printf "%s${dfmt}%s" "$color_esc" "$_duration" "$reset_esc"
            return
            ;;
    esac

    local bar_out=""
    (( width > 0 )) && bar_out=" $(bar "$_percent" "$width" "$bar_style")"

    local prefix="" pfmt="%.0f" dfmt="%s"
    if "$_short_mode"
    then
        pfmt="%2.0f"
        dfmt="%7s"
    elif "$one_line"
    then
        pfmt="%3.0f"
        dfmt="%6s"
    else
        prefix=$(printf '%7s ' "$short_period")
        pfmt="%2.0f"
    fi

    # Use "%%" so printf prints a literal "%"; a bare "%" would be
    # interpreted as the start of another conversion specifier.
    local pct="%%"
    if "$numbers_mode"
    then
        pct=""
    fi

    local dur_sep=" "
    [[ -z "$_duration" ]] && dur_sep=""

    # pfmt/dfmt/pct are controlled format fragments, not user input.
    printf "%s%s${pfmt}${pct}%s${dur_sep}${dfmt}%s" \
        "$color_esc" "$prefix" "$_percent" "$bar_out" "$_duration" "$reset_esc"
}

apply_option() {
    local short="$1" arg="${2:-}"
    case "$short" in
        h) usage; exit 0 ;;
        c) color_mode="color" ;;
        p) color_mode="plain" ;;
        d) date_mode=true ;;
        f) force=true ;;
        n) numbers_mode=true ;;
        1) one_line=true ;;
        s) display="short" ;;
        v|z|g)
            [[ "$bar_style_set" == true ]] && exit_fail "styles are exclusive"
            case "$short" in v) bar_style="vertical"   ;;
                             z) bar_style="horizontal" ;;
                             g) bar_style="gradient"   ;; esac
            bar_style_set=true
            ;;
        w) width="$arg" ;;
        *) exit_fail "unknown option: -$short" ;;
    esac
}

set_only_field() {
    local new="$1"
    [[ "$only_field" != "none" ]] \
        && exit_fail "--only-* options are mutually exclusive"
    only_field="$new"
}

set_only_period() {
    local new="$1"
    [[ "$only_period" != "all" ]] \
        && exit_fail "--only-rolling/-weekly/-monthly are mutually exclusive"
    only_period="$new"
}

render_output() {
    # Reads and renders the "period,percent,resetsAt" CSV lines from stdin.
    # Uses the shared state globals documented above parse_args.

    _use_color=false
    case "$color_mode" in
        auto)  [[ -t 1 ]] && _use_color=true  ;;
        color)               _use_color=true  ;;
        plain)               _use_color=false ;;
    esac

    _short_mode=false
    [[ "$display" = "short" ]] && _short_mode=true

    local ts_prefix=""
    if "$date_mode"
    then
        if "$one_line"
        then
            ts_prefix="$(timestamp "$numbers_mode"), "
        else
            ts_prefix="$(timestamp "$numbers_mode") "
        fi
    fi

    local timedate joined=""
    while IFS=, read -r _period _percent timedate
    do
        if [[ "$only_period" != "all" && "$_period" != "$only_period" ]]
        then
            continue
        fi

        if [[ "$only_field" = "bar" || "$only_field" = "percent" ]]
        then
            _duration=""
        elif "$numbers_mode"
        then
            _duration=$(seconds_until_iso "$timedate")
        elif "$_short_mode" || "$one_line"
        then
            _duration=$(human_readable_short "$timedate")
        else
            _duration=$(human_readable "$timedate")
        fi

        local line
        line=$(format_entry)
        if "$one_line"
        then
            joined="${joined:+$joined, }$line"
        else
            printf '%s\n' "${ts_prefix}${line}"
        fi
    done

    if "$one_line" && [[ -n "$joined" ]]
    then
        printf '%s\n' "${ts_prefix}${joined}"
    fi
}

load_lines() {
    local cache_path
    cache_path=$(cache_file)
    local now mtime=0
    now=$(date +%s)

    if [[ -f "$cache_path" ]]
    then
        mtime=$(mtime_seconds "$cache_path" 2>/dev/null) || mtime=0
        mtime=${mtime:-0}
    fi

    if [[ "$force" != true ]] && (( now - mtime < cache_filename_ttl ))
    then
        read_cache "$cache_path"
    else
        fetch_api "$cache_path"
    fi
}

validate_width() {
    if [[ -z "$width" ]]  # Default width: 0 for compact views, 8 otherwise
    then
        if [[ "$display"    = "short"   || "$one_line"   = true
           || "$only_field" = "percent" || "$only_field" = "datetime" ]]
        then
            width=0
        else
            width=8
        fi
    fi

    [[ "$width" =~ ^[0-9]+$ ]] \
        || exit_fail "width must be a number (got '$width')"
    (( width < 0 || width > 13 )) \
        && exit_fail "width must be between 0 and 13 (got '$width')"
    [[ "$display" = "short" && "$one_line" = true ]] \
        && exit_fail "--short and --one-line are mutually exclusive"
    [[ "$only_field" = "bar" && "$width" = "0" ]] \
        && exit_fail "--only-bar can't be used with -w 0 (bar would be empty)"

    # Explicit return 0 to prevent return codes leaking.  For example,
    # `fn_that_returns_1 && fn_wont_run` won't run `fn_wont_run` but will
    # return code 1 out of the function because fn_that_returns_1 ran last.
    return 0
}

parse_args() {
    # Reset shared-state globals to defaults on each invocation so repeated
    # calls (e.g. in tests) don't see stale values.
    bar_style="vertical"
    bar_style_set=false
    color_mode="auto"
    date_mode=false
    display="full"
    force=false
    numbers_mode=false
    one_line=false
    only_period="all"
    only_field="none"
    width=""

    # Separate short and long options before dispatching. Only -w/--width
    # take values, so those two forms must consume their following argument.
    local -a short_args=()
    local -a long_args=()
    while (( $# > 0 ))
    do
        case "$1" in
            --width)
                (( $# < 2 )) && exit_fail "--width requires a value"
                long_args+=("$1" "$2")
                shift 2
                ;;
            --width=*|--*)
                long_args+=("$1")
                shift
                ;;
            -w)
                (( $# < 2 )) && exit_fail "-w requires a value"
                short_args+=("$1" "$2")
                shift 2
                ;;
            -*)
                if [[ "$1" == "-" ]]
                then
                    usage
                    exit_fail "unknown argument: '-'"
                fi
                short_args+=("$1")
                shift
                ;;
            *)
                usage
                exit_fail "unknown argument: '$1'"
                ;;
        esac
    done

    local OPTIND=1 OPTARG="" opt
    while getopts "$_optstring" opt "${short_args[@]}"
    do
        case "$opt" in
            \?) exit_fail "unknown option: -$OPTARG" ;;
             :) exit_fail "-$OPTARG requires a value" ;;
             *) if [[ "$opt" == "w" ]]
                then
                    apply_option "$opt" "$OPTARG"
                else
                    apply_option "$opt"
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
                    exit_fail "--width requires a value"
                fi
                apply_option "w" "$1"
                shift
                ;;
            --only-bar)      set_only_field  "bar"      ;;
            --only-percent)  set_only_field  "percent"  ;;
            --only-datetime) set_only_field  "datetime" ;;
            --only-rolling)  set_only_period "rolling"  ;;
            --only-weekly)   set_only_period "weekly"   ;;
            --only-monthly)  set_only_period "monthly"  ;;
            --*)
                local name="${arg#--}"
                local short
                short="${_long_alias[$name]:-}"
                if [[ -z "$short" ]]
                then
                    usage
                    exit_fail "unknown argument: '$arg'"
                fi
                if [[ "$short" == "w" ]]
                then
                    (( $# == 0 )) && exit_fail "--$name requires a value"
                    apply_option "$short" "$1"
                    shift
                else
                    apply_option "$short"
                fi
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    validate_width
    load_lines | render_output
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
    cd "$progdir" || exit 1
    main "$@"
fi
