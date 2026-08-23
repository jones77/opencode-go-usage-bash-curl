#!/usr/bin/env bash

set -euo pipefail

echo "sourcing .env to get \$OPENCODE_GO_API_KEY"

readonly progname="$(basename "${BASH_SOURCE[0]}")"
readonly progdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$progdir" || exit 1
source .env || exit 1

# Ensure the environment variable is present
# FIXME: Read from an .env file or ~/.local/share/opencode/auth.json
if [ -z "$OPENCODE_GO_API_KEY" ]
then
    echo "$progname: error: need a OPENCODE_GO_API_KEY environment variable."
    exit 1
fi

_format_duration() {
    declare -A args=(
        [day]=$1
        [hour]=$2
        [minute]=$3
        [second]=$4
    )
    local string=
    local unit value
    for unit in "${!args[@]}"
    do
        value=${args[$unit]}
        (( value == 0 )) && continue

        if [[ -n "$string" ]]
        then
            string="$string, "
        fi
        if (( value == 1 ))
        then
            string="$string$value $unit"
        else
            string="$string$value ${unit}s"
        fi
    done

    echo "$string"
}

human_readable() {
    # Your ISO 8601 target date (adjust as needed)
    local iso_date="$1"

    # 1. Convert target date and current time to seconds since epoch
    local target_seconds=$(gdate -d "$iso_date" +%s)
    local now_seconds=$(gdate +%s)

    # 2. Calculate the difference in seconds
    local diff=$((target_seconds - now_seconds))

    # Handle past dates safely
    if (( diff < 0 ))
    then
        echo "The target date has already passed!"
        return 0
    fi

    # 3. Break down seconds into days, hours, minutes, and seconds
    local days=$((diff / 86400))
    local hours=$(((diff % 86400) / 3600))
    local minutes=$(((diff % 3600) / 60))
    local seconds=$((diff % 60))

    _format_duration "$days" "$hours" "$minutes" "$seconds"
}

# Uses code from:
# https://www.cyberciti.biz/faq/repeat-a-character-in-bash-script-under-linux-unix/
_bar() {
    percent="$1"
    twenty_fourths_int=$(echo "scale=0; $percent / (100 / 24)" | bc -l)
    twenty_fourths_float=$(echo "$percent / (100 / 24)" | bc -l)

    fill="X"
    half="-"
    empty="."

    more_than_one_quarter=$(echo "$twenty_fourths_float - $twenty_fourths_int > 0.25" | bc -l)
    more_than_three_quarters=$(echo "$twenty_fourths_float - $twenty_fourths_int > 0.75" | bc -l)
    if (( more_than_one_quarter == 0 ))
    then
        last="$empty"
    elif (( more_than_one_quarter == 1 && more_than_three_quarters == 0 ))
    then
        last="$half"
    elif (( more_than_one_quarter == 1 && more_than_three_quarters == 1 ))
    then
        last="$fill"
    fi

    local fill_range=$(seq 1 $twenty_fourths_int)
    echo -n "["
    for i in $fill_range
    do
        echo -n "${fill}"
    done

    echo -n "$last"

    local empty_range=$(seq $twenty_fourths_int 24)
    for i in $empty_range
    do
        echo -n "${empty}"
    done
    echo -n "]"
}

main() {
    # Execute the request and grab the HTTP status code
    readonly response=$(curl -s -w "%{http_code}" -X GET "https://opencode.ai/zen/go/v1/usage" \
      -H "Authorization: Bearer $OPENCODE_GO_API_KEY" \
      -H "Accept: application/json")

    # Separate the HTTP status code from the JSON body
    readonly http_status="${response:${#response}-3}"
    readonly body="${response:0:${#response}-3}"

    if [ "$http_status" -ne 200 ]
    then
        echo "API Request Failed with Status: $http_status"
        echo "Response: $body"
        exit 1
    fi

    # Print formatted output using jq
    printf "usage\t\tresets\n\n"
    for i in "rolling" "weekly" "monthly"
    do
        percent="$(echo "$body" | jq -r ".usage.$i.percent")"
        bar=$(_bar "$percent")
        timedate="$(echo "$body" | jq -r ".usage.$i.resetsAt")"

        printf "%0.0f%% $i\t%s\n" "${percent}" "$timedate"
        printf "%s\t%s\n" "$bar" "$(human_readable "$timedate")"
        [[ "$i" != "monthly" ]] && echo
    done
}

main "$@"
