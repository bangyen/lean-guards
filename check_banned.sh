#!/bin/bash

# Search for banned proof/lint bypass markers in Lean source files.
# This script fails if any banned pattern is found.

check_pattern() {
    local pattern="$1"
    local message="$2"

    local matches
    matches=$(git grep -nE "$pattern" -- '*.lean')

    if [ -n "$matches" ]; then
        echo "ERROR: Found banned pattern: ${pattern}"
        echo "$message"
        echo "$matches"
        return 1
    fi

    return 0
}

if ! check_pattern "sorry" "Replace 'sorry' with complete proofs."; then
    exit 1
fi

if ! check_pattern "admit" "Replace 'admit' with complete proofs."; then
    exit 1
fi

if ! check_pattern "axiom" "Replace 'axiom' declarations with complete theorems."; then
    exit 1
fi

if ! check_pattern "nolint" "Remove 'nolint' suppressions and resolve the underlying lint issues."; then
    exit 1
fi

if ! check_pattern "set_option" "Remove file-level 'set_option' directives."; then
    exit 1
fi

if ! check_pattern "partial" "Remove 'partial' declarations and prove termination."; then
    exit 1
fi

if ! check_pattern "unsafe" "Remove 'unsafe' declarations."; then
    exit 1
fi

echo "✓ No banned keywords found in Lean source files."
exit 0
