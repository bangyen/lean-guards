#!/bin/bash

# Assert that each guard both rejects code it should reject and accepts code it
# should accept. Running the guards against clean repositories only proves the
# absence of false positives; these cases cover the other direction.
#
# Each case runs in a throwaway git repository, because every guard discovers
# files through `git grep` or `git ls-files` and would otherwise scan this one.

set -uo pipefail

# Without this, a call to a helper that does not exist yet (say, defined further
# down the file) prints "command not found" and the suite still reports success.
trap 'echo "FATAL: unexpected error on line $LINENO"; exit 1' ERR

GUARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
FAILURES=()

# Per-case environment for the guard under test, as NAME=VALUE entries. Set it
# immediately before a case; both helpers clear it afterwards so it cannot leak.
GUARD_ENV=()

CANONICAL_HEADER="/-
Copyright (c) 2026 Bangyen Pham. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Bangyen Pham
-/"

# Build a git repository holding a single Lean file, plus the lakefile that
# check_import.sh reads to discover its search roots.
make_repo() {
    local dir="$1" path="$2" body="$3"
    mkdir -p "$dir/$(dirname "$path")"
    printf '%s\n' "$body" > "$dir/$path"
    cat > "$dir/lakefile.toml" <<'LAKE'
name = "fixture"

[[lean_lib]]
name = "Fixture"
LAKE
    git -C "$dir" init -q
    git -C "$dir" add -A
    git -C "$dir" -c user.email=t@t -c user.name=t commit -q -m fixture
}

# Like make_repo, but takes alternating path/body pairs for the guards that
# reason about a file tree rather than a single file.
make_repo_multi() {
    local dir="$1"; shift
    while [[ $# -gt 0 ]]; do
        mkdir -p "$dir/$(dirname "$1")"
        printf '%s\n' "$2" > "$dir/$1"
        shift 2
    done
    cat > "$dir/lakefile.toml" <<'LAKE'
name = "fixture"

[[lean_lib]]
name = "Fixture"
LAKE
    git -C "$dir" init -q
    git -C "$dir" add -A
    git -C "$dir" -c user.email=t@t -c user.name=t commit -q -m fixture
}

# expect_reject_multi <name> <guard> <needle> <path> <body> [<path> <body>...]
expect_reject_multi() {
    local name="$1" guard="$2" needle="$3"; shift 3
    local dir out code guard_argv
    dir="$(mktemp -d)"
    make_repo_multi "$dir" "$@"
    read -r -a guard_argv <<< "$guard"
    guard_argv[0]="$GUARDS_DIR/${guard_argv[0]}"
    out="$(cd "$dir" && env ${GUARD_ENV[@]+"${GUARD_ENV[@]}"} "${guard_argv[@]}" 2>&1)"
    code=$?
    rm -rf "$dir"

    if [[ $code -eq 0 ]]; then
        FAIL=$((FAIL + 1)); FAILURES+=("$name: expected $guard to reject, but it passed")
    elif ! grep -qF "$needle" <<< "$out"; then
        FAIL=$((FAIL + 1)); FAILURES+=("$name: $guard rejected, but not for the expected reason (wanted \"$needle\")")
    else
        PASS=$((PASS + 1))
    fi
    GUARD_ENV=()
}

# expect_accept_multi <name> <guard> <path> <body> [<path> <body>...]
expect_accept_multi() {
    local name="$1" guard="$2"; shift 2
    local dir out code guard_argv
    dir="$(mktemp -d)"
    make_repo_multi "$dir" "$@"
    read -r -a guard_argv <<< "$guard"
    guard_argv[0]="$GUARDS_DIR/${guard_argv[0]}"
    out="$(cd "$dir" && env ${GUARD_ENV[@]+"${GUARD_ENV[@]}"} "${guard_argv[@]}" 2>&1)"
    code=$?
    rm -rf "$dir"

    if [[ $code -ne 0 ]]; then
        FAIL=$((FAIL + 1)); FAILURES+=("$name: expected $guard to accept, but it rejected:"$'\n'"$out")
    else
        PASS=$((PASS + 1))
    fi
    GUARD_ENV=()
}

# expect_reject <name> <guard> <expected-output-substring> <lean-path> <body>
# The substring assertion matters: a guard that fails for an unrelated reason
# (missing file, syntax error) still exits non-zero and would pass without it.
expect_reject() {
    local name="$1" guard="$2" needle="$3" path="$4" body="$5"
    local dir out code guard_argv
    dir="$(mktemp -d)"
    make_repo "$dir" "$path" "$body"
    read -r -a guard_argv <<< "$guard"
    guard_argv[0]="$GUARDS_DIR/${guard_argv[0]}"
    out="$(cd "$dir" && env ${GUARD_ENV[@]+"${GUARD_ENV[@]}"} "${guard_argv[@]}" 2>&1)"
    code=$?
    rm -rf "$dir"

    if [[ $code -eq 0 ]]; then
        FAIL=$((FAIL + 1)); FAILURES+=("$name: expected $guard to reject, but it passed")
    elif ! grep -qF "$needle" <<< "$out"; then
        FAIL=$((FAIL + 1)); FAILURES+=("$name: $guard rejected, but not for the expected reason (wanted \"$needle\")")
    else
        PASS=$((PASS + 1))
    fi
    GUARD_ENV=()
}

# expect_accept <name> <guard> <lean-path> <body>
expect_accept() {
    local name="$1" guard="$2" path="$3" body="$4"
    local dir out code guard_argv
    dir="$(mktemp -d)"
    make_repo "$dir" "$path" "$body"
    read -r -a guard_argv <<< "$guard"
    guard_argv[0]="$GUARDS_DIR/${guard_argv[0]}"
    out="$(cd "$dir" && env ${GUARD_ENV[@]+"${GUARD_ENV[@]}"} "${guard_argv[@]}" 2>&1)"
    code=$?
    rm -rf "$dir"

    if [[ $code -ne 0 ]]; then
        FAIL=$((FAIL + 1)); FAILURES+=("$name: expected $guard to accept, but it rejected:"$'\n'"$out")
    else
        PASS=$((PASS + 1))
    fi
    GUARD_ENV=()
}

# check_config validates .guards.env rather than Lean sources, so it gets a
# repository holding that file instead of a fixture module.
expect_config() {
    local name="$1" outcome="$2" needle="$3" body="$4"
    local dir out code
    dir="$(mktemp -d)"
    printf '%s\n' "$body" > "$dir/.guards.env"
    out="$(cd "$dir" && "$GUARDS_DIR/check_config.sh" 2>&1)"
    code=$?
    rm -rf "$dir"

    if [[ "$outcome" == reject && $code -eq 0 ]]; then
        FAIL=$((FAIL + 1)); FAILURES+=("$name: expected check_config.sh to reject, but it passed")
    elif [[ "$outcome" == reject ]] && ! grep -qF "$needle" <<< "$out"; then
        FAIL=$((FAIL + 1)); FAILURES+=("$name: check_config.sh rejected, but not for the expected reason (wanted \"$needle\")")
    elif [[ "$outcome" == accept && $code -ne 0 ]]; then
        FAIL=$((FAIL + 1)); FAILURES+=("$name: expected check_config.sh to accept, but it rejected:"$'\n'"$out")
    else
        PASS=$((PASS + 1))
    fi
}

# --- check_banned -----------------------------------------------------------

expect_reject "banned/sorry" check_banned.sh "banned pattern" Fixture/A.lean \
'theorem t : True := by sorry'

expect_accept "banned/clean" check_banned.sh Fixture/A.lean \
'theorem t : True := by trivial'

# --- check_simp -------------------------------------------------------------

expect_reject "simp/unsqueezed" check_simp.sh "unsqueezed" Fixture/A.lean \
'theorem t : True := by simp'

expect_accept "simp/squeezed" check_simp.sh Fixture/A.lean \
'theorem t : True := by simp only [] <;> trivial'

# --- check_naming -----------------------------------------------------------

expect_reject "naming/snake_case def" check_naming.sh "camelCase" Fixture/A.lean \
'def foo_bar : Nat := 0'

expect_accept "naming/camelCase def" check_naming.sh Fixture/A.lean \
'def fooBar : Nat := 0'

# --- check_long_file --------------------------------------------------------

LONG_BODY="$(for i in $(seq 1 40); do echo "-- filler line $i"; done)"

# Drive the thresholds down rather than committing a fixture hundreds of lines
# long. The same fixture passing under a high cap and failing under a low one
# also shows the thresholds are honoured, not merely accepted.
GUARD_ENV=(MAX_LEAN_FILE_LINES=20 SOFT_LEAN_FILE_MAX_LINES=15 SOFT_LEAN_FILE_MIN_LINES=1)
expect_reject "long_file/over hard limit" check_long_file.sh "longer than hard limit" Fixture/A.lean \
"$LONG_BODY"

GUARD_ENV=(MAX_LEAN_FILE_LINES=100 SOFT_LEAN_FILE_MAX_LINES=90 SOFT_LEAN_FILE_MIN_LINES=1)
expect_accept "long_file/under hard limit" check_long_file.sh Fixture/A.lean \
"$LONG_BODY"

# --- check_description ------------------------------------------------------

expect_reject "description/missing module doc" check_description.sh "missing module doc" Fixture/A.lean \
'theorem foo_bar : True := trivial'

expect_reject "description/theorem not listed" check_description.sh "is not listed in the Theorems section" Fixture/A.lean \
'/-!
# Fixture

## Theorems

- `something_else`
-/

theorem foo_bar : True := trivial'

expect_accept "description/theorem listed" check_description.sh Fixture/A.lean \
'/-!
# Fixture

## Theorems

- `foo_bar`
-/

theorem foo_bar : True := trivial'

# A prime in the declaration name. The pre-fix regex stopped at the apostrophe,
# read the documented name as `foo` and the declaration as `foo'`, and reported
# a mismatch on a correctly documented file.
expect_accept "description/prime identifier documented" check_description.sh Fixture/A.lean \
"/-!
# Fixture

## Theorems

- \`foo_bar'\`
-/

theorem foo_bar' : True := trivial"

# --- check_copyright --------------------------------------------------------

expect_reject "copyright/missing header" check_copyright.sh "copyright header" Fixture/A.lean \
'theorem t : True := trivial'

expect_accept "copyright/canonical header" check_copyright.sh Fixture/A.lean \
"$CANONICAL_HEADER

theorem t : True := trivial"

# A near-miss: right shape, wrong text. The header is compared exactly, so this
# must still be rejected.
expect_reject "copyright/altered header" check_copyright.sh "copyright header" Fixture/A.lean \
'/-
Copyright (c) 2026 Someone Else. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Someone Else
-/

theorem t : True := trivial'

# --- check_proof_length -----------------------------------------------------

# Advisory by default; only a hard cap fails. Both cases set one so the check
# has a definite outcome rather than warning either way.
LONG_PROOF="theorem t : True := by
$(for i in $(seq 1 12); do echo "  -- step $i"; done)
  trivial"

GUARD_ENV=(HARD_PROOF_MAX_LINES=5 SOFT_PROOF_MIN_LINES=1 SOFT_PROOF_MAX_LINES=4)
expect_reject "proof_length/over hard cap" check_proof_length.sh "hard limit" Fixture/A.lean \
"$LONG_PROOF"

GUARD_ENV=(HARD_PROOF_MAX_LINES=50 SOFT_PROOF_MIN_LINES=1 SOFT_PROOF_MAX_LINES=40)
expect_accept "proof_length/under hard cap" check_proof_length.sh Fixture/A.lean \
"$LONG_PROOF"

# --- format_lean ------------------------------------------------------------

expect_reject "format/trailing whitespace" "format_lean.sh --check" "require formatting" Fixture/A.lean \
'theorem t : True := trivial   '

expect_reject "format/unsorted imports" "format_lean.sh --check" "require formatting" Fixture/A.lean \
'import Fixture.Zebra
import Fixture.Alpha

theorem t : True := trivial'

expect_accept "format/clean" "format_lean.sh --check" Fixture/A.lean \
'import Fixture.Alpha
import Fixture.Zebra

theorem t : True := trivial'

# --- check_import -----------------------------------------------------------

# Fixture/Sub.lean is the aggregator for Fixture/Sub/; omitting the child import
# is the violation.
expect_reject_multi "import/aggregator missing child" check_import.sh "missing 'import Fixture.Sub.Leaf'" \
    Fixture.lean 'import Fixture.Sub' \
    Fixture/Sub.lean '-- aggregator with no child import' \
    Fixture/Sub/Leaf.lean 'theorem t : True := trivial'

expect_accept_multi "import/aggregator complete" check_import.sh \
    Fixture.lean 'import Fixture.Sub' \
    Fixture/Sub.lean 'import Fixture.Sub.Leaf' \
    Fixture/Sub/Leaf.lean 'theorem t : True := trivial'

expect_reject_multi "import/aggregator absent" check_import.sh "Missing aggregator file" \
    Fixture.lean 'import Fixture.Sub.Leaf' \
    Fixture/Sub/Leaf.lean 'theorem t : True := trivial'

# --- check_banned word boundaries -------------------------------------------

# Bare substrings fired on ordinary names containing a banned word. These pin
# the boundary behaviour so the false positives cannot return.
expect_accept "banned/partialOrder is not partial" check_banned.sh Fixture/A.lean \
'def partialOrderThing : Nat := 0'

expect_accept "banned/axiomatic is not axiom" check_banned.sh Fixture/A.lean \
'def axiomaticFoo : Nat := 0'

expect_reject "banned/real partial still caught" check_banned.sh "banned pattern: partial" Fixture/A.lean \
'partial def loop : Nat -> Nat := fun n => loop n'

expect_reject "banned/native_decide" check_banned.sh "native_decide" Fixture/A.lean \
'theorem t : True := by native_decide'

expect_reject "banned/extern" check_banned.sh "extern" Fixture/A.lean \
'@[extern "c_impl"] def f : Nat := 0'

# --- check_config -----------------------------------------------------------

expect_config "config/valid" accept "" \
'MAX_LEAN_FILE_LINES=700
SOFT_LEAN_FILE_MAX_LINES=400'

# The bug this guard exists for: a misspelled name is ignored when sourced, so
# the repository silently runs on the default limit.
expect_config "config/unknown setting" reject "unknown setting" \
'MAX_LEAN_FILE_LINE=700'

expect_config "config/non-integer" reject "must be a non-negative integer" \
'MAX_LEAN_FILE_LINES=lots'

expect_config "config/soft above hard" reject "must be below MAX_LEAN_FILE_LINES" \
'MAX_LEAN_FILE_LINES=100
SOFT_LEAN_FILE_MAX_LINES=200'

expect_config "config/malformed line" reject "not a NAME=VALUE" \
'this is not an assignment'


# --- check_copyright parameterization ---------------------------------------

OTHER_HEADER='/-
Copyright (c) 2030 Ada Lovelace. All rights reserved.
Released under MIT license as described in the file LICENSE.
Authors: Ada Lovelace
-/

theorem t : True := trivial'

# The holder and year were hardcoded, so the guard only ever worked for one
# repository. Under a matching config another project's header is canonical.
GUARD_ENV=(COPYRIGHT_HOLDER="Ada Lovelace" COPYRIGHT_YEAR=2030 COPYRIGHT_LICENSE=MIT)
expect_accept "copyright/other holder configured" check_copyright.sh Fixture/A.lean \
"$OTHER_HEADER"

# The same file must still fail under the defaults.
expect_reject "copyright/other holder unconfigured" check_copyright.sh "copyright header" Fixture/A.lean \
"$OTHER_HEADER"

GUARD_ENV=(COPYRIGHT_YEAR=99)
expect_reject "copyright/bad year value" check_copyright.sh "four-digit year" Fixture/A.lean \
"$CANONICAL_HEADER

theorem t : True := trivial"

# --- check_config: non-integer settings --------------------------------------

expect_config "config/copyright settings valid" accept "" \
'COPYRIGHT_HOLDER=Ada Lovelace
COPYRIGHT_YEAR=2030'

expect_config "config/bad copyright year" reject "four-digit year" \
'COPYRIGHT_YEAR=20'

expect_config "config/empty holder" reject "must not be empty" \
'COPYRIGHT_HOLDER='

# A root that does not exist makes every guard scan nothing and pass, which is
# indistinguishable from a clean repository.
expect_config "config/nonexistent search root" reject "not a directory" \
'LEAN_SEARCH_ROOTS=NoSuchDir'

# --- summary ----------------------------------------------------------------

echo
if [[ $FAIL -gt 0 ]]; then
    echo "✗ ${FAIL} failed, ${PASS} passed"
    printf '  - %s\n' "${FAILURES[@]}"
    exit 1
fi

echo "✓ All ${PASS} guard tests passed."
