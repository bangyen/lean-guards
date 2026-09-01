# lean-guards

Shared quality-guard scripts for the Lean 4 projects `leansharp`, `leanbf`, and
`leanfunge`. The guard *logic* lives here once; each consuming repository keeps
its own *thresholds* in a `.guards.env` file at its root.

## Checks

| Script | Enforces |
| --- | --- |
| `check_config.sh` | `.guards.env` names real settings with valid values |
| `check_banned.sh` | No banned tactics, kernel-trust escapes, or bypass markers |
| `check_import.sh` | Every folder aggregator imports its direct children |
| `check_simp.sh` | `simp` usage follows project conventions |
| `check_copyright.sh` | Copyright headers present |
| `check_description.sh` | Module docstrings describe their declarations |
| `check_long_file.sh` | File length within hard/soft thresholds |
| `check_proof_length.sh` | Proof length within hard/soft thresholds |
| `check_naming.sh` | Naming conventions |
| `format_lean.sh` | Formatting (`--check` to verify without writing) |

`check_all.sh` runs them all in order, stopping at the first failure. The
config check runs first, since a typo there would leave every later guard on
its default threshold; format checking runs last, so style fixes cannot mask
earlier semantic failures.

## Use as a submodule

```bash
git submodule add https://github.com/bangyen/lean-guards.git scripts
git commit -m "chore: vendor shared guard scripts"
```

Run from the repository root:

```bash
./scripts/check_all.sh
```

In GitHub Actions, checkout must fetch the submodule:

```yaml
- uses: actions/checkout@v5
  with:
    submodules: true
```

After a fresh clone, initialize with `git submodule update --init`.

To take a newer version of the guards:

```bash
git -C scripts pull origin main
git add scripts && git commit -m "chore: bump lean-guards"
```

The submodule is pinned to a commit, so upstream changes never reach a
repository until that bump lands.

## Tests

`tests/run_tests.sh` asserts that each guard rejects code it should reject and
accepts code it should accept:

```bash
./tests/run_tests.sh
```

Running the guards against the consuming repositories only shows they produce
no false positives. These cases cover the other direction, which is how a guard
silently stops catching anything. Each case builds a throwaway git repository,
because every guard discovers files through `git grep` or `git ls-files`.

A rejection case asserts on the guard's message, not just its exit code — a
guard failing for an unrelated reason still exits non-zero.

All eleven guards are covered. Guards whose failure is gated behind a threshold
(`check_long_file`, `check_proof_length`) are tested from both sides — the same
fixture passing under a high cap and failing under a low one, which shows the
thresholds are honoured rather than merely accepted.

The suite is checked by mutation: neutering any guard, or making a one-line
change such as comparing four header lines instead of five, fails its cases.

## Shared CI workflow

`.github/workflows/lean-ci.yml` is a reusable workflow (`workflow_call`) that
builds a consuming repository, enforces a warning-free build, runs `lake lint`,
and runs the guards. Callers reduce to a stub:

```yaml
name: Lean Action CI

on:
  push:
  pull_request:
  workflow_dispatch:

jobs:
  build:
    uses: bangyen/lean-guards/.github/workflows/lean-ci.yml@v1
```

Pin the ref. At `@main` a change here would reach every consumer immediately,
which is the drift this repository exists to prevent.

Each consumer therefore holds **two independent pointers** into lean-guards:
the submodule commit (which guard *scripts* run) and the workflow ref (which CI
*shape* runs). They are bumped separately and may legitimately differ.

The workflow takes an optional `runs-on` input (default `ubuntu-latest`) and
requests only `contents: read`.

## Configuration

`check_all.sh` sources `.guards.env` from the consuming repo's root if present.

| Variable | Default | Meaning |
| --- | --- | --- |
| `LEAN_SEARCH_ROOTS` | `lean_lib` names in `lakefile.toml` | Directories to scan |
| `MAX_LEAN_FILE_LINES` | 250 | Hard file-length cap (fails) |
| `SOFT_LEAN_FILE_MAX_LINES` | 200 | Advisory file-length cap (warns) |
| `SOFT_LEAN_FILE_MIN_LINES` | 25 | Advisory file-length floor (warns) |
| `SOFT_SKIP_AGGREGATORS` | 1 | Skip soft checks on aggregator files |
| `HARD_PROOF_MAX_LINES` | 0 (off) | Hard proof-length cap (fails) |
| `SOFT_PROOF_MAX_LINES` | 100 | Advisory proof-length cap (warns) |
| `SOFT_PROOF_MIN_LINES` | 10 | Advisory proof-length floor (warns) |

Search roots are auto-detected from `lakefile.toml`, so `LEAN_SEARCH_ROOTS`
only needs setting when a repo wants a narrower set than its declared
libraries.

Example `.guards.env`:

```bash
MAX_LEAN_FILE_LINES=700
SOFT_LEAN_FILE_MAX_LINES=400
```
