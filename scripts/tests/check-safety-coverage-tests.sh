#!/bin/bash

set -euo pipefail

readonly script_directory=$(cd "$(dirname "$0")" && pwd -P)
readonly repository_root=$(cd "$script_directory/../.." && pwd -P)
readonly parser="$repository_root/scripts/check-safety-coverage.swift"
readonly fixture_root="$script_directory/fixtures/coverage"
readonly temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/mymaccleaner-coverage.XXXXXX")
readonly source_root="$temporary_root/Sources/SafetyContract"

if [[ -n "${CODEX_SANDBOX:-}" ]]; then
    readonly module_cache_root="${TMPDIR:-/tmp}/mymaccleaner-coverage-module-cache"
    mkdir -p "$module_cache_root"
    export CLANG_MODULE_CACHE_PATH="$module_cache_root/clang"
    export SWIFTPM_MODULECACHE_OVERRIDE="$module_cache_root/swiftpm"
fi

cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

mkdir -p "$source_root"
touch "$source_root/Alpha.swift"

coverage_input() {
    local fixture="$1"
    local output="$temporary_root/$(basename "$fixture")"

    sed "s|__SOURCE_ROOT__|$source_root|g" "$fixture" > "$output"
    printf '%s\n' "$output"
}

expect_pass() {
    local name="$1"
    shift

    if ! /usr/bin/swift "$parser" "$@" >/dev/null; then
        echo "Expected coverage gate to pass: $name" >&2
        exit 1
    fi
}

expect_fail() {
    local name="$1"
    shift

    if /usr/bin/swift "$parser" "$@" >/dev/null 2>&1; then
        echo "Expected coverage gate to fail: $name" >&2
        exit 1
    fi
}

below=$(coverage_input "$fixture_root/below-threshold.json")
at=$(coverage_input "$fixture_root/at-threshold.json")
above=$(coverage_input "$fixture_root/above-threshold.json")

expect_fail "below threshold" --input "$below" --source-root "$source_root" --minimum 80
expect_pass "at threshold" --input "$at" --source-root "$source_root" --minimum 80
expect_pass "above threshold" --input "$above" --source-root "$source_root" --minimum 80

printf '%s\n' '{"data":[{"files":[{"filename":"'"$source_root"'/Alpha.swift","summary":{"lines":{"count":10,"covered":8}}},{"filename":"'"$temporary_root"'/Tests/Ignored.swift","summary":{"lines":{"count":100,"covered":100}}}]}]}' > "$temporary_root/outside-root.json"
expect_pass "outside-root records are ignored" --input "$temporary_root/outside-root.json" --source-root "$source_root" --minimum 80

printf '%s\n' '{"data":[{"files":[{"filename":"'"$source_root"'/Alpha.swift","summary":{"lines":{"count":10,"covered":8}}},{"filename":"'"$source_root"'/Alpha.swift","summary":{"lines":{"count":10,"covered":8}}}]}]}' > "$temporary_root/duplicate-source.json"
expect_fail "duplicate matching source" --input "$temporary_root/duplicate-source.json" --source-root "$source_root" --minimum 80

printf '%s\n' '{not-json' > "$temporary_root/malformed.json"
expect_fail "malformed JSON" --input "$temporary_root/malformed.json" --source-root "$source_root" --minimum 80

printf '%s\n' '{"data":[{"files":[]}]}' > "$temporary_root/missing-source.json"
expect_fail "missing production source" --input "$temporary_root/missing-source.json" --source-root "$source_root" --minimum 80

printf '%s\n' '{"data":[{"files":[{"filename":"'"$source_root"'/Alpha.swift","summary":{"lines":{"count":0,"covered":0}}}]}]}' > "$temporary_root/zero-lines.json"
expect_fail "zero executable lines" --input "$temporary_root/zero-lines.json" --source-root "$source_root" --minimum 80

printf '%s\n' '{"data":[{"files":[{"filename":"'"$source_root"'/Alpha.swift","summary":{"lines":{"count":"ten","covered":8}}}]}]}' > "$temporary_root/non-numeric.json"
expect_fail "non-numeric counts" --input "$temporary_root/non-numeric.json" --source-root "$source_root" --minimum 80

expect_fail "zero threshold" --input "$at" --source-root "$source_root" --minimum 0
expect_fail "over-100 threshold" --input "$at" --source-root "$source_root" --minimum 101
expect_fail "non-numeric threshold" --input "$at" --source-root "$source_root" --minimum eighty

printf '%s\n' '{"data":[{"files":[{"filename":"'"$source_root"'/Alpha.swift","summary":{"lines":{"count":6000000000000000000,"covered":6000000000000000000}}}]}]}' > "$temporary_root/overflow.json"
expect_fail "overflowing threshold arithmetic" --input "$temporary_root/overflow.json" --source-root "$source_root" --minimum 80

touch "$source_root/Beta.swift"
expect_fail "missing one of two production sources" --input "$at" --source-root "$source_root" --minimum 80

for required_stage in \
    'run_canonical_gate()' \
    'verify-safety-contract-foundation-tests.sh' \
    '"$script_path" --source-only' \
    'run-safety-tests.sh" --enable-code-coverage --parallel' \
    '-newer "$freshness_marker"' \
    '"$llvm_profdata" merge' \
    '"$llvm_cov" export' \
    'check-safety-coverage.swift'; do
    if ! /usr/bin/grep -Fq "$required_stage" "$repository_root/scripts/verify-safety-contract.sh"; then
        echo "Canonical verifier is missing required stage: $required_stage" >&2
        exit 1
    fi
done

readonly workflow="$repository_root/.github/workflows/safety-contract.yml"
readonly documentation="$repository_root/docs/SAFETY-CONTRACT.md"
# The .planning validation artifact is intentionally absent from the sanitized public repo.
# It is checked below only when present (see the guarded block near the end of this file).
readonly validation="$repository_root/.planning/phases/00-safety-freeze-and-baseline-contract/00-VALIDATION.md"

for required_artifact in "$workflow" "$documentation"; do
    if [[ ! -f "$required_artifact" ]]; then
        echo "Missing safety contract artifact: ${required_artifact##*/}" >&2
        exit 1
    fi
done

for required_workflow_line in 'contents: read' 'persist-credentials: false' 'uses: actions/checkout@' 'runs-on: macos-26'; do
    if ! /usr/bin/grep -Fq "$required_workflow_line" "$workflow"; then
        echo "Safety workflow is missing: $required_workflow_line" >&2
        exit 1
    fi
done

if [[ $(/usr/bin/grep -Fxc '        run: bash scripts/verify-safety-contract.sh' "$workflow") -ne 1 ]]; then
    echo "Safety workflow must run the canonical command exactly once." >&2
    exit 1
fi

# Official checkout, pinned to a full 40-hex commit SHA, followed by its version comment.
readonly checkout_pin_pattern='^[[:space:]]*-[[:space:]]+uses:[[:space:]]+actions/checkout@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]+([.][0-9]+){0,2}[[:space:]]*$'
readonly sample_sha='3d3c42e5aac5ba805825da76410c181273ba90b1'

expect_checkout_pin() {
    local expected="$1" line="$2" actual=fail
    if /usr/bin/grep -Eq "$checkout_pin_pattern" <<<"$line"; then
        actual=pass
    fi
    if [[ "$actual" != "$expected" ]]; then
        echo "Checkout pin rule: expected $expected for: $line" >&2
        exit 1
    fi
}

expect_checkout_pin pass "      - uses: actions/checkout@$sample_sha # v4"
expect_checkout_pin pass "      - uses: actions/checkout@$sample_sha # v7.0.1"
expect_checkout_pin fail "      - uses: actions/checkout@v4"
expect_checkout_pin fail "      - uses: actions/checkout@$sample_sha"
expect_checkout_pin fail "      - uses: actions/checkout@${sample_sha:1} # v4"
expect_checkout_pin fail "      - uses: actions/checkout@$sample_sha # latest"
expect_checkout_pin fail "      - uses: other/checkout@$sample_sha # v4"

if [[ $(/usr/bin/grep -Ec '^[[:space:]]*-[[:space:]]+uses:' "$workflow") -ne 1 ]] \
    || ! /usr/bin/grep -Eq "$checkout_pin_pattern" "$workflow"; then
    echo "Safety workflow must use only official checkout." >&2
    exit 1
fi

if ! /usr/bin/awk '
    $0 == "permissions:" { inPermissions = 1; next }
    inPermissions && /^[^[:space:]]/ { exit valid ? 0 : 1 }
    inPermissions && /^  contents: read$/ && !valid { valid = 1; next }
    inPermissions && /^[[:space:]]/ && $0 !~ /^[[:space:]]*$/ { exit 1 }
    END { if (!inPermissions || !valid) exit 1 }
' "$workflow"; then
    echo "Safety workflow permissions are not read-only." >&2
    exit 1
fi

# Note: `xcode-select` is permitted (the runner must select the toolchain); `xcodebuild`
# remains prohibited so this minimal safety workflow cannot become a build/sign pipeline.
if /usr/bin/grep -Eqi '(actions/(cache|upload-artifact|download-artifact)|xcodebuild|notari[sz]|(^|[^[:alpha:]])sign|release|publish|secrets[.]|github_token|^[[:space:]]*run:.*git[[:space:]]+push)' "$workflow"; then
    echo "Safety workflow contains a prohibited capability." >&2
    exit 1
fi

for required_documentation_text in \
    'Disabled capability matrix' \
    'Five fixed read-only process adapters' \
    'Redacted diagnostics' \
    'No-network disabled routes' \
    'bash scripts/verify-safety-contract.sh' \
    'Full-Xcode' \
    'First hosted run'; do
    if ! /usr/bin/grep -Fq "$required_documentation_text" "$documentation"; then
        echo "Safety documentation is missing: $required_documentation_text" >&2
        exit 1
    fi
done

if [[ -f "$validation" ]]; then
    for required_validation_text in \
        'status: local-automated-evidence-complete' \
        'nyquist_compliant: true' \
        'wave_0_complete: true' \
        '00-10-03' \
        'Full-Xcode app/UI evidence is complete, or remains explicitly pending without a pass claim.' \
        'First hosted run is complete after private push, or remains explicitly pending without a pass claim.'; do
        if ! /usr/bin/grep -Fq "$required_validation_text" "$validation"; then
            echo "Safety validation is missing: $required_validation_text" >&2
            exit 1
        fi
    done
else
    echo "::notice::Skipping .planning 00-VALIDATION.md checks (artifact absent in this checkout)."
fi

echo "Safety coverage parser self-tests passed."
