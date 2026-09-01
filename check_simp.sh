#!/bin/bash

# Search for unsqueezed 'simp' variants in the source directories.
# This script encourages explicit squeeze tactics for better performance and stability.

MATCHES=$(git grep -nE '(^|[^a-zA-Z0-9_])(d?simp_all|d?simp|simpa)!?([^a-zA-Z0-9_]|$)' -- '*.lean' | \
  grep -vE '\b(d?simp_all|d?simp|simpa)!?(\?|.*only)\b' | \
  grep -vE '\[-?simp\]' | \
  grep -vE 'no_squeeze' | \
  grep -v 'trace\.')

if [ -n "$MATCHES" ]; then
    echo "ERROR: Found unsqueezed 'simp' variants in source directories."
    echo "Replace with 'simp only' or 'simp?' to improve proof stability."
    echo "$MATCHES"
    exit 1
fi

echo "✓ No unsqueezed simp variants found."
exit 0
