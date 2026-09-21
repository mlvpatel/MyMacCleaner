#!/bin/bash

set -euo pipefail

script_directory=$(cd "$(/usr/bin/dirname "$0")" && pwd -P)
readonly script_directory
repository_root=$(cd "$script_directory/.." && pwd -P)
readonly repository_root
readonly package_root="$repository_root/CleanerCore"
readonly coverage_checker="$script_directory/check-cleanercore-coverage.swift"
readonly fixture_sentinel="CLEANERCORE-GATE-SELF-TEST"

fail() {
    local rule_id="$1"
    printf '%s\n' "$rule_id" >&2
    exit 1
}

run_gate_command() {
    if [[ "${gate_mode:-normal}" != "fixture" ]]; then
        "$@"
        return
    fi

    local command_output
    local command_status
    local output_line
    if command_output=$("$@" 2>&1); then
        command_status=0
    else
        command_status=$?
    fi

    if [[ -n "$command_output" ]]; then
        while IFS= read -r output_line || [[ -n "$output_line" ]]; do
            printf 'CLEANERCORE-GATE-FIXTURE-OUTPUT: %s\n' "$output_line"
        done <<< "$command_output"
    fi
    return "$command_status"
}

run_stage() {
    local label="$1"
    shift

    printf 'CLEANERCORE-GATE: %s\n' "$label"
    run_gate_command "$@"
}

gate_mode="normal"
swift_bin=""
xcrun_bin=""
xcode_select_bin=""

if [[ $# -eq 0 ]]; then
    if [[ -n "${SWIFT_BIN+x}" || -n "${XCRUN_BIN+x}" || -n "${XCODE_SELECT_BIN+x}" ]]; then
        fail "CC-GATE-TOOL-OVERRIDE"
    fi
    swift_bin="/usr/bin/swift"
    xcrun_bin="/usr/bin/xcrun"
    xcode_select_bin="/usr/bin/xcode-select"
elif [[ $# -eq 1 && "$1" == "--fixture-tools" ]]; then
    [[ "${CLEANERCORE_GATE_SELF_TEST_SENTINEL:-}" == "$fixture_sentinel" ]] \
        || fail "CC-GATE-FIXTURE-AUTHORIZATION"
    gate_mode="fixture"
    swift_bin="${CLEANERCORE_FIXTURE_SWIFT_BIN:-}"
    xcrun_bin="${CLEANERCORE_FIXTURE_XCRUN_BIN:-}"
    xcode_select_bin="${CLEANERCORE_FIXTURE_XCODE_SELECT_BIN:-}"
else
    fail "CC-GATE-ARGUMENTS"
fi
readonly gate_mode swift_bin xcrun_bin xcode_select_bin

[[ -x "$swift_bin" ]] || fail "CC-GATE-SWIFT-TOOL"
[[ -x "$xcrun_bin" ]] || fail "CC-GATE-XCRUN-TOOL"
[[ -x "$xcode_select_bin" ]] || fail "CC-GATE-XCODE-SELECT-TOOL"
[[ -x "$repository_root/scripts/run-cleanercore-tests.sh" ]] || fail "CC-GATE-RUNNER"
[[ -x "$repository_root/scripts/verify-cleanercore-contract.sh" ]] || fail "CC-GATE-CONTRACT"
[[ -r "$repository_root/scripts/tests/verify-cleanercore-contract-tests.sh" ]] || fail "CC-GATE-CONTRACT-SELF-TEST"
[[ -r "$repository_root/scripts/tests/run-cleanercore-tests-tests.sh" ]] || fail "CC-GATE-RUNNER-SELF-TEST"
[[ -r "$repository_root/scripts/tests/check-cleanercore-coverage-tests.sh" ]] || fail "CC-GATE-COVERAGE-SELF-TEST"
[[ -f "$coverage_checker" && -r "$coverage_checker" ]] || fail "CC-GATE-COVERAGE-CHECKER"
[[ -d "$package_root/Sources" ]] || fail "CC-GATE-SOURCE-ROOT"

selected_developer_dir=$("$xcode_select_bin" -p 2>/dev/null) || fail "CC-GATE-DEVELOPER-DIR"
[[ -d "$selected_developer_dir" ]] || fail "CC-GATE-DEVELOPER-DIR"
developer_dir=$(/bin/realpath "$selected_developer_dir" 2>/dev/null) || fail "CC-GATE-DEVELOPER-DIR"
[[ -d "$developer_dir" && "$developer_dir" != "/" ]] || fail "CC-GATE-DEVELOPER-DIR"

reported_llvm_profdata=$("$xcrun_bin" --find llvm-profdata 2>/dev/null) || fail "CC-GATE-LLVM-TOOL"
reported_llvm_cov=$("$xcrun_bin" --find llvm-cov 2>/dev/null) || fail "CC-GATE-LLVM-TOOL"
llvm_profdata=$(/bin/realpath "$reported_llvm_profdata" 2>/dev/null) || fail "CC-GATE-LLVM-TOOL"
llvm_cov=$(/bin/realpath "$reported_llvm_cov" 2>/dev/null) || fail "CC-GATE-LLVM-TOOL"
[[ -x "$llvm_profdata" && -x "$llvm_cov" ]] || fail "CC-GATE-LLVM-TOOL"
case "$llvm_profdata" in
    "$developer_dir"/*) ;;
    *) fail "CC-GATE-LLVM-TRUST" ;;
esac
case "$llvm_cov" in
    "$developer_dir"/*) ;;
    *) fail "CC-GATE-LLVM-TRUST" ;;
esac

coverage_directory=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mymaccleaner-cleanercore-gate.XXXXXX") \
    || fail "CC-GATE-TEMPORARY"
coverage_directory=$(/bin/realpath "$coverage_directory" 2>/dev/null) || fail "CC-GATE-TEMPORARY"
cleanup() {
    /bin/rm -rf "$coverage_directory"
}
trap cleanup EXIT

scratch_path="$coverage_directory/swiftpm-scratch"
/bin/mkdir -p "$scratch_path" || fail "CC-GATE-TEMPORARY"
scratch_path=$(/bin/realpath "$scratch_path" 2>/dev/null) || fail "CC-GATE-TEMPORARY"
case "$scratch_path" in
    "$coverage_directory"/*) ;;
    *) fail "CC-GATE-TEMPORARY" ;;
esac

cd "$repository_root" || fail "CC-GATE-SOURCE-ROOT"

run_stage "source-contract-self-tests" /bin/bash "$repository_root/scripts/tests/verify-cleanercore-contract-tests.sh"
run_stage "runner-self-tests" /bin/bash "$repository_root/scripts/tests/run-cleanercore-tests-tests.sh"
run_stage "coverage-parser-self-tests" /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/tests/check-cleanercore-coverage-tests.sh"
run_stage "source-contract" /bin/bash "$repository_root/scripts/verify-cleanercore-contract.sh"

run_stage \
    "phase-5-01" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter 'PolicyDispositionTests|PolicyRankingTests|CapabilityCardTests'
run_stage \
    "phase-5-02" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter 'CleanupPlanTests|ApprovalBindingTests'
run_stage \
    "phase-5-03" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter 'PolicyGoldenTests|PlanInvalidationPropertyTests'
run_stage \
    "phase-6-01" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter TrashOperationAuthorityTests
run_stage \
    "phase-6-02" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter TrashRevalidationTests
run_stage \
    "phase-6-03" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter TrashExecutionTests
run_stage \
    "phase-6-04" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter FoundationTrashAdapterTests
run_stage \
    "phase-6-05" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter TrashExecutionHostileFixtureTests
run_stage \
    "phase-7-receipts" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter 'ReceiptTransitionTests|ReceiptStoreAdapterTests|ReceiptCoordinatorTests|ReceiptReconciliationTests|ReceiptPrivacyTests|ReceiptRetentionTests|ReceiptHistoryDeletionTests|ReceiptRecoveryTests|ReceiptHostileFixtureTests'

run_stage \
    "phase-3-01-01" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter HuggingFaceInventoryTests
run_stage \
    "phase-3-01-02" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter 'HuggingFaceHostileFixtureTests|ModelStoreAuthorityTests'
run_stage \
    "phase-3-02-01" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter OllamaInventoryTests
run_stage \
    "phase-3-02-02" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter 'SelectedModelRootTests|ModelStoreAuthorityTests'
run_stage \
    "phase-3-03-01" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter AIModelHostileFixtureTests
run_stage \
    "phase-3-03-02" \
    /usr/bin/env CODEX_SANDBOX=1 /bin/bash "$repository_root/scripts/run-cleanercore-tests.sh" \
    --filter 'ModelStoreAuthorityTests|AIModelHostileFixtureTests'

freshness_marker="$coverage_directory/profiles-before-test"
/usr/bin/touch "$freshness_marker" || fail "CC-GATE-TEMPORARY"
run_stage \
    "swiftpm-tests-with-coverage" \
    /usr/bin/env \
    -u SWIFT_BIN \
    -u XCRUN_BIN \
    -u XCODE_SELECT_BIN \
    CODEX_SANDBOX=1 \
    /bin/bash \
    "$repository_root/scripts/run-cleanercore-tests.sh" \
    --enable-code-coverage \
    --no-parallel \
    --scratch-path "$scratch_path"

# The classic SwiftPM layout emits a single merged CleanerCorePackageTests.xctest under
# .build/debug; Xcode 27's build system emits one *Tests.xctest bundle per test target
# under out/Products/Debug. Accept both by matching every *Tests test binary, and require
# at least one that is executable and newer than the freshness marker.
test_binaries=()
while IFS= read -r -d '' candidate; do
    test_binaries+=("$candidate")
done < <(/usr/bin/find "$scratch_path" -type f -path '*Tests.xctest/Contents/MacOS/*Tests' -not -path '*.dSYM/*' -print0)
[[ ${#test_binaries[@]} -ge 1 ]] || fail "CC-GATE-TEST-BINARY"
for test_binary in "${test_binaries[@]}"; do
    [[ -x "$test_binary" && "$test_binary" -nt "$freshness_marker" ]] || fail "CC-GATE-TEST-BINARY"
done

# Coverage profiles live under a codecov directory in both layouts (.build/debug/codecov
# and out/Products/Debug/codecov), so match on the codecov segment rather than "debug".
profile_paths=()
while IFS= read -r -d '' candidate; do
    profile_paths+=("$candidate")
done < <(/usr/bin/find "$scratch_path" -type f -path '*/codecov/*.profraw' -print0)
[[ ${#profile_paths[@]} -gt 0 ]] || fail "CC-GATE-COVERAGE-PROFILE"
for profile_path in "${profile_paths[@]}"; do
    [[ "$profile_path" -nt "$freshness_marker" ]] || fail "CC-GATE-COVERAGE-PROFILE"
done

coverage_profile="$coverage_directory/coverage.profdata"
coverage_json="$coverage_directory/coverage.json"
printf 'CLEANERCORE-GATE: %s\n' "coverage-profile-merge"
"$llvm_profdata" merge -sparse "${profile_paths[@]}" -o "$coverage_profile" > "$coverage_directory/llvm-profdata.log" 2>&1 \
    || fail "CC-GATE-COVERAGE-PROFILE"
[[ -s "$coverage_profile" ]] || fail "CC-GATE-COVERAGE-PROFILE"
printf 'CLEANERCORE-GATE: %s\n' "coverage-export"
# Pass every discovered test binary to llvm-cov: the first positionally and the rest via
# -object, so coverage merges across all per-target bundles (Xcode 27) or the single merged
# bundle (classic layout). Built as an index loop for bash 3.2 (no empty-array expansion).
export_objects=("${test_binaries[0]}")
export_index=1
while (( export_index < ${#test_binaries[@]} )); do
    export_objects+=(-object "${test_binaries[$export_index]}")
    export_index=$(( export_index + 1 ))
done
"$llvm_cov" export -instr-profile "$coverage_profile" "${export_objects[@]}" > "$coverage_json" 2> "$coverage_directory/llvm-cov.log" \
    || fail "CC-GATE-COVERAGE-EXPORT"
[[ -s "$coverage_json" ]] || fail "CC-GATE-COVERAGE-EXPORT"

/bin/mkdir -p "$coverage_directory/module-cache"
printf 'CLEANERCORE-GATE: %s\n' "coverage-decision-pure"
run_gate_command \
    /usr/bin/env \
    CLANG_MODULE_CACHE_PATH="$coverage_directory/module-cache/clang" \
    SWIFTPM_MODULECACHE_OVERRIDE="$coverage_directory/module-cache/swiftpm" \
    "$swift_bin" "$coverage_checker" \
        --input "$coverage_json" \
        --source-root "$package_root/Sources" \
        --minimum 80 \
    || fail "CC-GATE-COVERAGE-DECISION"

printf 'CLEANERCORE-GATE: %s\n' "coverage-decision-foundation"
run_gate_command \
    /usr/bin/env \
    CLANG_MODULE_CACHE_PATH="$coverage_directory/module-cache/clang" \
    SWIFTPM_MODULECACHE_OVERRIDE="$coverage_directory/module-cache/swiftpm" \
    "$swift_bin" "$coverage_checker" \
        --input "$coverage_json" \
        --source-root "$package_root/Sources" \
        --minimum 80 \
    || fail "CC-GATE-COVERAGE-DECISION"

printf 'CLEANERCORE-GATE: %s\n' "coverage-decision"
run_gate_command \
    /usr/bin/env \
    CLANG_MODULE_CACHE_PATH="$coverage_directory/module-cache/clang" \
    SWIFTPM_MODULECACHE_OVERRIDE="$coverage_directory/module-cache/swiftpm" \
    "$swift_bin" "$coverage_checker" \
        --input "$coverage_json" \
        --source-root "$package_root/Sources" \
        --minimum 80 \
    || fail "CC-GATE-COVERAGE-DECISION"

if [[ "$gate_mode" == "fixture" ]]; then
    printf 'CLEANERCORE-GATE: FIXTURE PASS\n'
else
    printf 'CLEANERCORE-GATE: PASS\n'
fi
