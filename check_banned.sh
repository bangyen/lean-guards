#!/bin/bash

# Search for banned proof/lint bypass markers in Lean source files.
# This script fails if any banned pattern is found.
#
# Patterns match whole words only. As bare substrings they fired on ordinary
# names that merely contain a banned word -- `partialOrder` tripped `partial`,
# `axiomatic` tripped `axiom` -- and a guard that rejects valid code gets
# worked around.

check_pattern() {
    local pattern="$1"
    local message="$2"

    local matches
    matches=$(git grep -nwE "$pattern" -- '*.lean')

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

# Kernel-trust escapes: these make a proof depend on compiled code or an
# unchecked implementation rather than on the kernel.
if ! check_pattern "native_decide" "Replace 'native_decide' with 'decide' or an explicit proof; it trusts the compiler."; then
    exit 1
fi

if ! check_pattern "implemented_by" "Remove '@[implemented_by]'; it swaps in unverified code."; then
    exit 1
fi

if ! check_pattern "extern" "Remove '@[extern]' declarations; they trust foreign code."; then
    exit 1
fi

echo "✓ No banned keywords found in Lean source files."
exit 0
