#!/bin/bash

# Check theorem/lemma proof block lengths with advisory thresholds.
# By default this script warns (does not fail) when proofs look too short/long.
#
# Environment variables:
# - SOFT_PROOF_MIN_LINES: advisory minimum proof block lines (default: 4)
# - SOFT_PROOF_MAX_LINES: advisory maximum proof block lines (default: 120)
# - HARD_PROOF_MAX_LINES: hard maximum proof block lines (default: 0, disabled)

set -euo pipefail

SOFT_MIN_LINES="${SOFT_PROOF_MIN_LINES:-10}"
SOFT_MAX_LINES="${SOFT_PROOF_MAX_LINES:-100}"
HARD_MAX_LINES="${HARD_PROOF_MAX_LINES:-0}"

for value_name in SOFT_MIN_LINES SOFT_MAX_LINES HARD_MAX_LINES; do
    value="${!value_name}"
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "ERROR: ${value_name} must be a non-negative integer."
        exit 1
    fi
done

if [ "$SOFT_MIN_LINES" -eq 0 ]; then
    echo "ERROR: SOFT_PROOF_MIN_LINES must be greater than 0."
    exit 1
fi

if [ "$SOFT_MIN_LINES" -gt "$SOFT_MAX_LINES" ]; then
    echo "ERROR: SOFT_PROOF_MIN_LINES must be less than or equal to SOFT_PROOF_MAX_LINES."
    exit 1
fi

if [ "$HARD_MAX_LINES" -ne 0 ] && [ "$SOFT_MAX_LINES" -gt "$HARD_MAX_LINES" ]; then
    echo "ERROR: SOFT_PROOF_MAX_LINES must be <= HARD_PROOF_MAX_LINES when hard max is enabled."
    exit 1
fi

SOFT_LOW_MATCHES=()
SOFT_HIGH_MATCHES=()
HARD_MATCHES=()

collect_proof_blocks() {
    local file_path="$1"

    awk -v file_path="$file_path" '
        function extract_decl_name(line,   cleaned, pieces) {
            cleaned = line
            sub(/^[[:space:]]*(protected[[:space:]]+)?(theorem|lemma)[[:space:]]+/, "", cleaned)
            split(cleaned, pieces, /[^A-Za-z0-9_.]/)
            return pieces[1]
        }
        function starts_theorem_or_lemma(line) {
            return line ~ /^[[:space:]]*(protected[[:space:]]+)?(theorem|lemma)[[:space:]]+/
        }
        function starts_toplevel_block(line) {
            return line ~ /^[[:space:]]*(\/--|theorem|lemma|def|abbrev|class|structure|instance|inductive|axiom|example|namespace|section|end|open|variable|set_option|attribute|local)\b/
        }
        function flush_block(last_line,   span) {
            if (!in_block) {
                return
            }
            span = last_line - block_start_line + 1
            if (span > 0) {
                printf "%s:%d-%d:%s:%d\n", file_path, block_start_line, last_line, block_name, span
            }
            in_block = 0
            block_name = ""
            block_start_line = 0
        }
        {
            if (starts_theorem_or_lemma($0)) {
                flush_block(NR - 1)
                in_block = 1
                block_start_line = NR
                block_name = extract_decl_name($0)
                next
            }

            if (in_block && starts_toplevel_block($0)) {
                flush_block(NR - 1)
            }
        }
        END {
            flush_block(NR)
        }
    ' "$file_path"
}

while IFS= read -r file_path; do
    [ -z "$file_path" ] && continue

    while IFS= read -r block_info; do
        [ -z "$block_info" ] && continue
        line_span="${block_info##*:}"
        if [ "$HARD_MAX_LINES" -ne 0 ] && [ "$line_span" -gt "$HARD_MAX_LINES" ]; then
            HARD_MATCHES+=("$block_info")
        fi

        if [ "$line_span" -lt "$SOFT_MIN_LINES" ]; then
            SOFT_LOW_MATCHES+=("$block_info")
        elif [ "$line_span" -gt "$SOFT_MAX_LINES" ]; then
            SOFT_HIGH_MATCHES+=("$block_info")
        fi
    done < <(collect_proof_blocks "$file_path")
done < <(git ls-files '*.lean')

if [ "${#SOFT_LOW_MATCHES[@]}" -gt 0 ] || [ "${#SOFT_HIGH_MATCHES[@]}" -gt 0 ]; then
    echo "WARN: Some theorem/lemma proof blocks are outside advisory range ${SOFT_MIN_LINES}-${SOFT_MAX_LINES} lines."
    echo "These warnings do not fail CI, but they can highlight opportunities to simplify or split proofs."
    if [ "${#SOFT_LOW_MATCHES[@]}" -gt 0 ]; then
        echo "WARN: Proof blocks below advisory minimum:"
        printf "%s\n" "${SOFT_LOW_MATCHES[@]}"
    fi
    if [ "${#SOFT_HIGH_MATCHES[@]}" -gt 0 ]; then
        echo "WARN: Proof blocks above advisory maximum:"
        printf "%s\n" "${SOFT_HIGH_MATCHES[@]}"
    fi
fi

if [ "${#HARD_MATCHES[@]}" -gt 0 ]; then
    echo "ERROR: Found theorem/lemma proof blocks longer than hard limit ${HARD_MAX_LINES} lines."
    echo "Consider splitting long proofs into helper lemmas."
    printf "%s\n" "${HARD_MATCHES[@]}"
    exit 1
fi

if [ "$HARD_MAX_LINES" -eq 0 ]; then
    echo "✓ Proof length advisory check completed (${SOFT_MIN_LINES}-${SOFT_MAX_LINES} lines, hard max disabled)."
else
    echo "✓ Proof length advisory check completed (${SOFT_MIN_LINES}-${SOFT_MAX_LINES} lines, hard max ${HARD_MAX_LINES})."
fi
exit 0
