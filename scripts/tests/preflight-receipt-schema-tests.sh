#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd -P)
preflight="$repo_root/scripts/preflight-receipt-schema.sh"
fixtures="$repo_root/scripts/tests/fixtures/receipt-preflight"
sentinel="RECEIPT-PREFLIGHT-SELF-TEST"

expect_success() {
    local label="$1"
    shift

    if "$@" > /tmp/mymaccleaner-receipt-preflight-success.out 2>&1; then
        return 0
    fi

    echo "Expected success: $label" >&2
    cat /tmp/mymaccleaner-receipt-preflight-success.out >&2
    exit 1
}

expect_failure() {
    local label="$1"
    local expected_rule="$2"
    shift 2

    local output
    if output=$("$@" 2>&1); then
        echo "Expected failure: $label" >&2
        exit 1
    fi

    if ! /usr/bin/grep -Fq "$expected_rule" <<<"$output"; then
        echo "Expected $expected_rule for $label" >&2
        echo "$output" >&2
        exit 1
    fi
}

fixture_success() {
    local label="$1"
    local path="$2"

    expect_success "$label" env RECEIPT_PREFLIGHT_SELF_TEST_SENTINEL="$sentinel" \
        "$preflight" --fixture-root "$path"
}

fixture_failure() {
    local label="$1"
    local expected_rule="$2"
    local path="$3"

    expect_failure "$label" "$expected_rule" env RECEIPT_PREFLIGHT_SELF_TEST_SENTINEL="$sentinel" \
        "$preflight" --fixture-root "$path"
}

fixture_success "passing synthetic map" "$fixtures/safe"
fixture_failure "missing source" "CC-RECEIPT-PREFLIGHT-MISSING-SOURCE" "$fixtures/missing-source"
fixture_failure "stale hash" "CC-RECEIPT-PREFLIGHT-STALE-HASH" "$fixtures/stale-hash"
fixture_failure "unmapped declaration" "CC-RECEIPT-PREFLIGHT-UNMAPPED" "$fixtures/unmapped"
fixture_failure "duplicate map identity" "CC-RECEIPT-PREFLIGHT-DUPLICATE" "$fixtures/duplicate"
fixture_failure "optionality mismatch" "CC-RECEIPT-PREFLIGHT-OPTIONALITY" "$fixtures/optionality"
fixture_failure "AST parse failure" "CC-RECEIPT-PREFLIGHT-AST-FAILURE" "$fixtures/ast-failure"

expect_failure "missing sentinel" "CC-RECEIPT-PREFLIGHT-AUTHORIZATION" \
    "$preflight" --fixture-root "$fixtures/safe"
expect_failure "unknown argument" "CC-RECEIPT-PREFLIGHT-ARGUMENTS" \
    "$preflight" --unknown

echo "Receipt schema preflight self-tests passed."
