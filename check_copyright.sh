#!/bin/bash

# Check that all Lean files start with the required copyright header block.
# This script fails if any file has a missing or non-standard header.
#
# Environment variables:
# - COPYRIGHT_HOLDER: name in the copyright and Authors lines (default: Bangyen Pham)
# - COPYRIGHT_YEAR: year in the copyright line (default: 2026)
# - COPYRIGHT_LICENSE: license phrase (default: Apache 2.0)
#
# The header is compared exactly, so bumping the year means rewriting it in
# every file. That is the intended strictness: the header is either canonical
# or it is not.

COPYRIGHT_HOLDER="${COPYRIGHT_HOLDER:-Bangyen Pham}"
COPYRIGHT_YEAR="${COPYRIGHT_YEAR:-2026}"
COPYRIGHT_LICENSE="${COPYRIGHT_LICENSE:-Apache 2.0}"

if ! [[ "$COPYRIGHT_YEAR" =~ ^[0-9]{4}$ ]]; then
    echo "ERROR: COPYRIGHT_YEAR must be a four-digit year, got '${COPYRIGHT_YEAR}'."
    exit 1
fi

EXPECTED_HEADER="$(cat <<EOF
/-
Copyright (c) ${COPYRIGHT_YEAR} ${COPYRIGHT_HOLDER}. All rights reserved.
Released under ${COPYRIGHT_LICENSE} license as described in the file LICENSE.
Authors: ${COPYRIGHT_HOLDER}
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
