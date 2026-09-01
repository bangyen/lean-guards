#!/bin/bash

# Validate .guards.env before the other guards read it.
#
# The file is sourced by check_all.sh, so a typo does not fail loudly: an
# unknown name is simply ignored and the guard silently uses its default. A
# repository that meant to raise its file-length cap would appear to pass while
# actually running under the stock limit.
#
# Checks that every assignment names a variable a guard reads, that values are
# well formed, and that soft thresholds sit below their hard counterparts.

set -uo pipefail

CONFIG_FILE="${GUARDS_ENV_FILE:-.guards.env}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "✓ No ${CONFIG_FILE} to validate; guards run with their defaults."
    exit 0
fi

KNOWN=(
    LEAN_SEARCH_ROOTS
    MAX_LEAN_FILE_LINES
    SOFT_LEAN_FILE_MIN_LINES
    SOFT_LEAN_FILE_MAX_LINES
    SOFT_SKIP_AGGREGATORS
    HARD_PROOF_MAX_LINES
    SOFT_PROOF_MIN_LINES
    SOFT_PROOF_MAX_LINES
    COPYRIGHT_HOLDER
    COPYRIGHT_YEAR
    COPYRIGHT_LICENSE
)

INTEGER_VARS=(
    MAX_LEAN_FILE_LINES
    SOFT_LEAN_FILE_MIN_LINES
    SOFT_LEAN_FILE_MAX_LINES
    SOFT_SKIP_AGGREGATORS
    HARD_PROOF_MAX_LINES
    SOFT_PROOF_MIN_LINES
    SOFT_PROOF_MAX_LINES
)

MATCHES=()
lineno=0

contains() {
    local needle="$1"; shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue

    if [[ ! "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*= ]]; then
        MATCHES+=("${CONFIG_FILE}:${lineno}: not a NAME=VALUE assignment: ${line}")
        continue
    fi

    name="${line%%=*}"
    name="${name//[[:space:]]/}"
    value="${line#*=}"
    value="${value%\"}"; value="${value#\"}"

    if ! contains "$name" "${KNOWN[@]}"; then
        MATCHES+=("${CONFIG_FILE}:${lineno}: unknown setting '${name}'; no guard reads it")
        continue
    fi

    # An unquoted value containing spaces makes `source` try to run the second
    # word as a command, leaving the variable empty and the guard on defaults.
    if [[ "$value" == *[[:space:]]* && ! "$value" =~ ^\".*\"$ && ! "$value" =~ ^\'.*\'$ ]]; then
        raw_value="${line#*=}"
        if [[ ! "$raw_value" =~ ^[[:space:]]*[\"\'] ]]; then
            MATCHES+=("${CONFIG_FILE}:${lineno}: ${name} contains spaces and must be quoted: ${name}=\"${value}\"")
            continue
        fi
    fi

    if contains "$name" "${INTEGER_VARS[@]}" && ! [[ "$value" =~ ^[0-9]+$ ]]; then
        MATCHES+=("${CONFIG_FILE}:${lineno}: ${name} must be a non-negative integer, got '${value}'")
    fi

    # The non-integer settings previously passed unchecked, so a typo here was
    # silently accepted and then quietly did the wrong thing.
    if [[ "$name" == COPYRIGHT_YEAR ]] && ! [[ "$value" =~ ^[0-9]{4}$ ]]; then
        MATCHES+=("${CONFIG_FILE}:${lineno}: COPYRIGHT_YEAR must be a four-digit year, got '${value}'")
    fi

    if [[ "$name" == COPYRIGHT_HOLDER || "$name" == COPYRIGHT_LICENSE ]] && [[ -z "${value//[[:space:]]/}" ]]; then
        MATCHES+=("${CONFIG_FILE}:${lineno}: ${name} must not be empty")
    fi

    # A root that is not a directory means the guards scan nothing and pass
    # vacuously, which looks identical to a clean repository.
    if [[ "$name" == LEAN_SEARCH_ROOTS ]]; then
        if [[ -z "${value//[[:space:]]/}" ]]; then
            MATCHES+=("${CONFIG_FILE}:${lineno}: LEAN_SEARCH_ROOTS must not be empty")
        else
            read -r -a roots <<< "$value"
            for root in "${roots[@]}"; do
                if [[ ! -d "$root" ]]; then
                    MATCHES+=("${CONFIG_FILE}:${lineno}: LEAN_SEARCH_ROOTS names '${root}', which is not a directory")
                fi
            done
        fi
    fi
done < "$CONFIG_FILE"

if [[ ${#MATCHES[@]} -eq 0 ]]; then
    # Cross-field checks run only once the individual values are known good.
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    hard_file="${MAX_LEAN_FILE_LINES:-250}"
    soft_file_max="${SOFT_LEAN_FILE_MAX_LINES:-200}"
    soft_file_min="${SOFT_LEAN_FILE_MIN_LINES:-25}"
    hard_proof="${HARD_PROOF_MAX_LINES:-0}"
    soft_proof_max="${SOFT_PROOF_MAX_LINES:-100}"
    soft_proof_min="${SOFT_PROOF_MIN_LINES:-10}"

    if [[ "$soft_file_max" -ge "$hard_file" ]]; then
        MATCHES+=("SOFT_LEAN_FILE_MAX_LINES (${soft_file_max}) must be below MAX_LEAN_FILE_LINES (${hard_file})")
    fi
    if [[ "$soft_file_min" -gt "$soft_file_max" ]]; then
        MATCHES+=("SOFT_LEAN_FILE_MIN_LINES (${soft_file_min}) must not exceed SOFT_LEAN_FILE_MAX_LINES (${soft_file_max})")
    fi
    if [[ "$hard_proof" -ne 0 && "$soft_proof_max" -ge "$hard_proof" ]]; then
        MATCHES+=("SOFT_PROOF_MAX_LINES (${soft_proof_max}) must be below HARD_PROOF_MAX_LINES (${hard_proof})")
    fi
    if [[ "$soft_proof_min" -gt "$soft_proof_max" ]]; then
        MATCHES+=("SOFT_PROOF_MIN_LINES (${soft_proof_min}) must not exceed SOFT_PROOF_MAX_LINES (${soft_proof_max})")
    fi
fi

# The Lean headers and the LICENSE file are two copies of the same fact, and
# they had already drifted: two repositories carried Apache headers under an MIT
# LICENSE. Checking them against each other is the only thing that keeps them
# honest, since neither side can notice the other changing.
if [[ ${#MATCHES[@]} -eq 0 && -f LICENSE ]]; then
    license_name="${COPYRIGHT_LICENSE:-Apache 2.0}"
    case "$license_name" in
        "Apache 2.0"|Apache-2.0) license_pattern="Apache License" ;;
        MIT) license_pattern="MIT License" ;;
        *)  license_pattern="" ;;
    esac

    if [[ -n "$license_pattern" ]] && ! grep -qF "$license_pattern" LICENSE; then
        MATCHES+=("COPYRIGHT_LICENSE is '${license_name}', but LICENSE does not look like a ${license_pattern}")
    fi

    holder="${COPYRIGHT_HOLDER:-Bangyen Pham}"
    if [[ -z "${holder//[[:space:]]/}" ]]; then
        MATCHES+=("COPYRIGHT_HOLDER resolved to an empty value; check that it is quoted in ${CONFIG_FILE}")
    elif ! grep -qF "$holder" LICENSE; then
        MATCHES+=("COPYRIGHT_HOLDER is '${holder}', but that name does not appear in LICENSE")
    fi
fi

if [[ ${#MATCHES[@]} -gt 0 ]]; then
    echo "ERROR: Invalid ${CONFIG_FILE}."
    printf "%s\n" "${MATCHES[@]}"
    exit 1
fi

echo "✓ ${CONFIG_FILE} is valid."
exit 0
