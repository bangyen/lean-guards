#!/bin/bash

# Run all quality guard scripts in a consistent order.
# Stops on the first failure and returns a non-zero exit code.
#
# Runs from the consuming repository's root. Per-repo thresholds live in
# .guards.env there; this script sources that file when it exists, so the
# shared guard logic stays identical across repositories while each one keeps
# its own limits.

set -euo pipefail

GUARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Guards run as separate processes, so config must be exported to reach them.
if [[ -f .guards.env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .guards.env
    set +a
fi

# Keep format check last so style fixes do not hide earlier semantic failures.
SCRIPTS=(
    "check_banned.sh"
    "check_import.sh"
    "check_simp.sh"
    "check_copyright.sh"
    "check_description.sh"
    "check_long_file.sh"
    "check_proof_length.sh"
    "check_naming.sh"
    "format_lean.sh --check"
)

for entry in "${SCRIPTS[@]}"; do
    echo "==> Running: ${entry}"
    read -r -a parts <<< "${entry}"
    script="${parts[0]}"
    parts[0]="${GUARDS_DIR}/${script}"
    "${parts[@]}"
done

echo "✓ All guard checks passed."
