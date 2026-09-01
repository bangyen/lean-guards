#!/bin/bash

# Check that all Lean files start with the required copyright header block.
# This script fails if any file has a missing or non-standard header.

EXPECTED_HEADER="$(cat <<'EOF'
/-
Copyright (c) 2026 Bangyen Pham. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Bangyen Pham
-/
EOF
)"

MATCHES=()

while IFS= read -r file_path; do
    [ -z "$file_path" ] && continue

    actual_header="$(awk 'NR <= 5 { print }' "$file_path")"
    if [ "$actual_header" != "$EXPECTED_HEADER" ]; then
        MATCHES+=("$file_path")
    fi
done < <(git ls-files '*.lean')

if [ "${#MATCHES[@]}" -gt 0 ]; then
    echo "ERROR: Missing or invalid copyright header block in Lean files."
    echo "Expected the canonical 5-line header at the top of each file."
    printf "%s\n" "${MATCHES[@]}"
    exit 1
fi

echo "✓ All Lean files include the canonical copyright header block."
exit 0
