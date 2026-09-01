#!/bin/bash

# Check Lean file lengths with hard and soft thresholds.
# Hard max fails CI; soft min/max emit warnings only.
#
# Environment variables:
# - MAX_LEAN_FILE_LINES: hard maximum line count (default: 250)
# - SOFT_LEAN_FILE_MIN_LINES: advisory minimum line count (default: 20)
# - SOFT_LEAN_FILE_MAX_LINES: advisory maximum line count (default: 250)
# - SOFT_SKIP_AGGREGATORS: if 1, skip soft checks for aggregator files (default: 1)

HARD_MAX_LINES="${MAX_LEAN_FILE_LINES:-250}"
SOFT_MIN_LINES="${SOFT_LEAN_FILE_MIN_LINES:-25}"
SOFT_MAX_LINES="${SOFT_LEAN_FILE_MAX_LINES:-200}"
SOFT_SKIP_AGGREGATORS="${SOFT_SKIP_AGGREGATORS:-1}"

for value_name in HARD_MAX_LINES SOFT_MIN_LINES SOFT_MAX_LINES; do
    value="${!value_name}"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -le 0 ]; then
        echo "ERROR: ${value_name} must be a positive integer."
        exit 1
    fi
done

if [ "$SOFT_MIN_LINES" -gt "$SOFT_MAX_LINES" ]; then
    echo "ERROR: SOFT_LEAN_FILE_MIN_LINES must be less than or equal to SOFT_LEAN_FILE_MAX_LINES."
    exit 1
fi

if [ "$SOFT_MAX_LINES" -ge "$HARD_MAX_LINES" ]; then
    echo "ERROR: SOFT_LEAN_FILE_MAX_LINES must be smaller than MAX_LEAN_FILE_LINES."
    exit 1
fi

if ! [[ "$SOFT_SKIP_AGGREGATORS" =~ ^[01]$ ]]; then
    echo "ERROR: SOFT_SKIP_AGGREGATORS must be 0 or 1."
    exit 1
fi

HARD_MATCHES=()
SOFT_LOW_MATCHES=()
SOFT_HIGH_MATCHES=()

is_aggregator_file() {
    file_path="$1"
    aggregator_dir="${file_path%.lean}"
    [ -d "$aggregator_dir" ]
}

while IFS= read -r file_path; do
    [ -z "$file_path" ] && continue

    line_count="$(wc -l < "$file_path" | tr -d ' ')"
    if [ "$line_count" -gt "$HARD_MAX_LINES" ]; then
        HARD_MATCHES+=("$file_path:$line_count")
    fi

    if [ "$SOFT_SKIP_AGGREGATORS" -eq 1 ] && is_aggregator_file "$file_path"; then
        continue
    fi

    if [ "$line_count" -lt "$SOFT_MIN_LINES" ]; then
        SOFT_LOW_MATCHES+=("$file_path:$line_count")
    elif [ "$line_count" -gt "$SOFT_MAX_LINES" ]; then
        SOFT_HIGH_MATCHES+=("$file_path:$line_count")
    fi
done < <(git ls-files '*.lean')

if [ "${#SOFT_LOW_MATCHES[@]}" -gt 0 ] || [ "${#SOFT_HIGH_MATCHES[@]}" -gt 0 ]; then
    echo "WARN: Some Lean files are outside the advisory range ${SOFT_MIN_LINES}-${SOFT_MAX_LINES} lines."
    echo "These warnings do not fail CI, but can indicate opportunities to consolidate or split modules."
    if [ "${#SOFT_LOW_MATCHES[@]}" -gt 0 ]; then
        echo "WARN: Files below advisory minimum:"
        printf "%s\n" "${SOFT_LOW_MATCHES[@]}"
    fi
    if [ "${#SOFT_HIGH_MATCHES[@]}" -gt 0 ]; then
        echo "WARN: Files above advisory maximum:"
        printf "%s\n" "${SOFT_HIGH_MATCHES[@]}"
    fi
fi

if [ "${#HARD_MATCHES[@]}" -gt 0 ]; then
    echo "ERROR: Found Lean files longer than hard limit ${HARD_MAX_LINES} lines."
    echo "Split large files into smaller modules where possible."
    printf "%s\n" "${HARD_MATCHES[@]}"
    exit 1
fi

echo "✓ All Lean files are within hard limit ${HARD_MAX_LINES} lines."
echo "✓ Advisory range check completed (${SOFT_MIN_LINES}-${SOFT_MAX_LINES} lines)."
exit 0
