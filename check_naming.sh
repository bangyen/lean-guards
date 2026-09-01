#!/bin/bash

# Check that Lean declarations follow mathlib naming conventions.
# - def: lowerCamelCase (functions) or UpperCamelCase (properties/types)
# - structure/class: UpperCamelCase
# - theorem/lemma: snake_case (excluded from this check)
#
# This script specifically targets def, structure, and class declarations
# that use snake_case, which is a common mathlib violation. It catches both
# lowercase-starting names (foo_bar) and capitalized snake_case (L_toy).

MATCHES=$(git grep -nE '^[[:space:]]*(noncomputable[[:space:]]+)?(def|structure|class)[[:space:]]+[A-Za-z0-9]+_[A-Za-z0-9_]*' -- '*.lean')

if [ -n "$MATCHES" ]; then
    echo "ERROR: Found declarations that should be in camelCase but use snake_case."
    echo " - use lowerCamelCase for functions/values"
    echo " - use UpperCamelCase for structures/classes/properties"
    echo "$MATCHES"
    exit 1
fi

echo "✓ All targeted declarations follow camelCase naming conventions."
exit 0
