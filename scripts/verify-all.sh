#!/bin/bash
# Runs what .github/workflows/safety-contract.yml runs, in the same order, so a local pass predicts CI.
#
# Usage: bash scripts/verify-all.sh [--fast]
#   --fast  Source contracts and verifier self-tests only. Skips the SafetyContract and CleanerCore
#           Swift test runs and their 80% coverage gates, so it is not what CI runs.
#
# The PR Checks workflow (app build, unit tests with the coverage ratchet, SwiftLint) needs full
# Xcode and is not part of this script; CONTRIBUTING.md lists its local commands.

set -euo pipefail

repository_root=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$repository_root"

usage() {
    printf 'usage: bash scripts/verify-all.sh [--fast]\n' >&2
    exit 64
}

fast=0
if [[ $# -gt 1 ]]; then
    usage
elif [[ $# -eq 1 ]]; then
    [[ "$1" == "--fast" ]] || usage
    fast=1
fi

run_step() {
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        printf '::group::%s\n' "$*"
    else
        printf '\n==> %s\n' "$*"
    fi
    "$@"
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        printf '::endgroup::\n'
    fi
}

if [[ $fast -eq 1 ]]; then
    run_step bash scripts/verify-safety-contract.sh --source-only
else
    run_step bash scripts/verify-safety-contract.sh
    run_step bash scripts/verify-cleanercore.sh
fi
run_step bash scripts/verify-cleanercore-contract.sh
run_step bash scripts/verify-adaptive-bridge.sh
run_step bash scripts/verify-adaptive-experience.sh

# Self-tests that validate verifier behavior against .planning artifacts skip cleanly (with a
# ::notice::) when those artifacts are absent, so this stays blocking for verifier regressions.
for self_test in scripts/tests/*.sh; do
    run_step bash "$self_test"
done

if [[ $fast -eq 1 ]]; then
    printf '\nVERIFY-ALL: PASS (fast: no Swift tests or coverage)\n'
else
    printf '\nVERIFY-ALL: PASS\n'
fi
