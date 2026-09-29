#!/bin/bash

set -euo pipefail

script_directory=$(cd "$(dirname "$0")" && pwd -P)
readonly script_directory
repository_root=$(cd "$script_directory/../.." && pwd -P)
readonly repository_root
readonly parser="$repository_root/scripts/check-cleanercore-coverage.swift"
readonly verifier="$repository_root/scripts/verify-cleanercore.sh"
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/mymaccleaner-cleanercore-coverage.XXXXXX")
readonly temporary_root
readonly source_root="$temporary_root/CleanerCore/Sources"
readonly pure_root="$source_root/CleanerCore"
readonly foundation_root="$source_root/CleanerCoreFoundation"
readonly darwin_root="$source_root/CleanerCoreDarwin"
readonly content_root="$source_root/CleanerCoreContentAdapter"

if [[ -n "${CODEX_SANDBOX:-}" ]]; then
    readonly module_cache_root="${TMPDIR:-/tmp}/mymaccleaner-cleanercore-coverage-module-cache"
    mkdir -p "$module_cache_root"
    export CLANG_MODULE_CACHE_PATH="$module_cache_root/clang"
    export SWIFTPM_MODULECACHE_OVERRIDE="$module_cache_root/swiftpm"
fi

cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

mkdir -p \
    "$pure_root/sub" \
    "$pure_root/Generated" \
    "$foundation_root" \
    "$darwin_root" \
    "$content_root"
touch \
    "$pure_root/Alpha.swift" \
    "$pure_root/Generated/Ignored.swift" \
    "$foundation_root/Beta.swift" \
    "$darwin_root/Darwin.swift" \
    "$content_root/Content.swift"

write_four_target_report() {
    local output="$1"
    local alpha_count="$2"
    local alpha_covered="$3"
    local beta_count="$4"
    local beta_covered="$5"
    local darwin_count="$6"
    local darwin_covered="$7"
    local content_count="$8"
    local content_covered="$9"

    printf '%s\n' \
        '{"data":[{"files":[{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{"count":'"$alpha_count"',"covered":'"$alpha_covered"'}}},{"filename":"'"$foundation_root"'/Beta.swift","summary":{"lines":{"count":'"$beta_count"',"covered":'"$beta_covered"'}}},{"filename":"'"$darwin_root"'/Darwin.swift","summary":{"lines":{"count":'"$darwin_count"',"covered":'"$darwin_covered"'}}},{"filename":"'"$content_root"'/Content.swift","summary":{"lines":{"count":'"$content_count"',"covered":'"$content_covered"'}}}]}]}' \
        > "$output"
}

write_nonproduction_inflation_report() {
    local output="$1"
    local extra_path="$2"

    printf '%s\n' \
        '{"data":[{"files":[{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{"count":50,"covered":39}}},{"filename":"'"$foundation_root"'/Beta.swift","summary":{"lines":{"count":50,"covered":39}}},{"filename":"'"$darwin_root"'/Darwin.swift","summary":{"lines":{"count":50,"covered":39}}},{"filename":"'"$content_root"'/Content.swift","summary":{"lines":{"count":50,"covered":39}}},{"filename":"'"$extra_path"'","summary":{"lines":{"count":1000,"covered":1000}}}]}]}' \
        > "$output"
}

expect_pass() {
    local label="$1"
    shift

    if ! /usr/bin/swift "$parser" "$@" > "$temporary_root/$label.out"; then
        echo "Expected CleanerCore coverage gate to pass: $label" >&2
        exit 1
    fi
}

expect_fail() {
    local label="$1"
    shift

    if /usr/bin/swift "$parser" "$@" > "$temporary_root/$label.out" 2>&1; then
        echo "Expected CleanerCore coverage gate to fail: $label" >&2
        exit 1
    fi
}

expect_fail_with_rule() {
    local label="$1"
    local expected_rule="$2"
    shift 2

    local output
    local status
    set +e
    output=$(/usr/bin/swift "$parser" "$@" 2>&1)
    status=$?
    set -e

    if [[ "$status" -eq 0 ]]; then
        echo "Expected CleanerCore coverage gate to fail: $label" >&2
        exit 1
    fi
    if [[ "$output" != *"$expected_rule"* ]]; then
        echo "Expected $expected_rule from CleanerCore coverage gate: $label" >&2
        exit 1
    fi
}

expect_command_failure() {
    local label="$1"
    local expected="$2"
    shift 2

    local command_output
    local command_exit
    set +e
    command_output=$("$@" 2>&1)
    command_exit=$?
    set -e

    if [[ "$command_exit" -eq 0 ]]; then
        echo "Expected command to fail: $label" >&2
        exit 1
    fi
    if [[ "$command_output" != *"$expected"* ]]; then
        echo "Expected $expected from failing command: $label" >&2
        exit 1
    fi
}

below="$temporary_root/below.json"
exact="$temporary_root/exact.json"
above="$temporary_root/above.json"
write_four_target_report "$below" 50 39 50 39 50 39 50 39
write_four_target_report "$exact" 50 40 50 40 50 40 50 40
write_four_target_report "$above" 50 41 50 41 50 41 50 41

expect_fail_with_rule "aggregate-below-threshold" "CC-COVERAGE-BELOW-MINIMUM" \
    --input "$below" \
    --source-root "$source_root" \
    --minimum 80
expect_pass "exact-threshold" --input "$exact" --source-root "$source_root" --minimum 80
expect_pass "above-threshold" --input "$above" --source-root "$source_root" --minimum 80

touch "$pure_root/Omitted.swift"
expect_fail_with_rule "missing-individual-production-source" "CC-COVERAGE-MISSING-SOURCE: CleanerCore" \
    --input "$exact" \
    --source-root "$source_root" \
    --minimum 80
rm -f "$pure_root/Omitted.swift"

touch "$foundation_root/CryptoKitPlanDigestAdapter.swift"
expect_fail_with_rule "missing-cryptokit-plan-digest-adapter" "CC-COVERAGE-MISSING-SOURCE: CleanerCoreFoundation" \
    --input "$exact" \
    --source-root "$source_root" \
    --minimum 80
rm -f "$foundation_root/CryptoKitPlanDigestAdapter.swift"

declaration_fixture="$darwin_root/DarwinMemorySystem.swift"
mkdir -p "$(dirname "$declaration_fixture")"
cp "$repository_root/CleanerCore/Sources/CleanerCoreDarwin/DarwinMemorySystem.swift" "$declaration_fixture"
expect_pass "known-declaration-only-source" \
    --input "$exact" \
    --source-root "$source_root" \
    --minimum 80
printf '%s\n' 'struct ExecutableDrift {' '    func run() { }' '}' > "$declaration_fixture"
expect_fail_with_rule "declaration-only-executable-drift" "CC-COVERAGE-DECLARATION-DRIFT: CleanerCoreDarwin" \
    --input "$exact" \
    --source-root "$source_root" \
    --minimum 80
rm -f "$declaration_fixture"

write_four_target_report "$temporary_root/pure-below-target.json" 100 79 100 100 100 100 100 100
expect_fail_with_rule "pure-target-below-threshold" "CC-COVERAGE-BELOW-MINIMUM: CleanerCore" \
    --input "$temporary_root/pure-below-target.json" \
    --source-root "$source_root" \
    --minimum 80

write_four_target_report "$temporary_root/foundation-below-target.json" 100 100 100 79 100 100 100 100
expect_fail_with_rule \
    "foundation-target-below-threshold" \
    "CC-COVERAGE-BELOW-MINIMUM: CleanerCoreFoundation" \
    --input "$temporary_root/foundation-below-target.json" \
    --source-root "$source_root" \
    --minimum 80

write_four_target_report "$temporary_root/darwin-below-target.json" 100 100 100 100 50 39 100 100
expect_fail_with_rule "darwin-target-below-threshold" "CC-COVERAGE-BELOW-MINIMUM: CleanerCoreDarwin" \
    --input "$temporary_root/darwin-below-target.json" \
    --source-root "$source_root" \
    --minimum 80

write_four_target_report "$temporary_root/content-below-target.json" 100 100 100 100 100 100 50 39
expect_fail_with_rule \
    "content-target-below-threshold" \
    "CC-COVERAGE-BELOW-MINIMUM: CleanerCoreContentAdapter" \
    --input "$temporary_root/content-below-target.json" \
    --source-root "$source_root" \
    --minimum 80

expected_exact_report=$'CLEANERCORE-COVERAGE: PASS aggregate 160/200 (80.00%)\nCLEANERCORE-COVERAGE: CleanerCore 40/50 (80.00%)\nCLEANERCORE-COVERAGE: CleanerCoreFoundation 40/50 (80.00%)\nCLEANERCORE-COVERAGE: CleanerCoreDarwin 40/50 (80.00%)\nCLEANERCORE-COVERAGE: CleanerCoreContentAdapter 40/50 (80.00%)'
if [[ $(< "$temporary_root/exact-threshold.out") != "$expected_exact_report" ]]; then
    echo "CleanerCore coverage output is not stable." >&2
    exit 1
fi

for nonproduction_case in outside test generated build; do
    case "$nonproduction_case" in
        outside) nonproduction_path="$temporary_root/OutsideCoverage.swift" ;;
        test) nonproduction_path="$temporary_root/CleanerCore/Tests/IgnoredTests.swift" ;;
        generated) nonproduction_path="$pure_root/Generated/Ignored.swift" ;;
        build) nonproduction_path="$temporary_root/CleanerCore/.build/Ignored.swift" ;;
    esac
    write_nonproduction_inflation_report \
        "$temporary_root/$nonproduction_case-inflation.json" \
        "$nonproduction_path"
    expect_fail_with_rule "$nonproduction_case-cannot-inflate" "CC-COVERAGE-BELOW-MINIMUM" \
        --input "$temporary_root/$nonproduction_case-inflation.json" \
        --source-root "$source_root" \
        --minimum 80
done

unknown_target_root="$source_root/CleanerCoreUnknown"
mkdir -p "$unknown_target_root"
touch "$unknown_target_root/Unknown.swift"
printf '%s\n' \
    '{"data":[{"files":[{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$foundation_root"'/Beta.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$darwin_root"'/Darwin.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$content_root"'/Content.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$unknown_target_root"'/Unknown.swift","summary":{"lines":{"count":1000,"covered":1000}}}]}]}' \
    > "$temporary_root/unknown-target.json"
expect_fail_with_rule "unknown-target" "CC-COVERAGE-UNKNOWN-TARGET" \
    --input "$temporary_root/unknown-target.json" \
    --source-root "$source_root" \
    --minimum 80

printf '%s\n' \
    '{"data":[{"files":[{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$foundation_root"'/Beta.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$darwin_root"'/Darwin.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$content_root"'/Content.swift","summary":{"lines":{"count":50,"covered":40}}}]}]}' \
    > "$temporary_root/identical-duplicate.json"
expect_fail_with_rule "identical-duplicate" "CC-COVERAGE-DUPLICATE-SOURCE" \
    --input "$temporary_root/identical-duplicate.json" \
    --source-root "$source_root" \
    --minimum 80

printf '%s\n' \
    '{"data":[{"files":[{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$pure_root"'/sub/../Alpha.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$foundation_root"'/Beta.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$darwin_root"'/Darwin.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$content_root"'/Content.swift","summary":{"lines":{"count":50,"covered":40}}}]}]}' \
    > "$temporary_root/normalized-duplicate.json"
expect_fail_with_rule "normalized-identical-duplicate" "CC-COVERAGE-DUPLICATE-SOURCE" \
    --input "$temporary_root/normalized-duplicate.json" \
    --source-root "$source_root" \
    --minimum 80

printf '%s\n' \
    '{"data":[{"files":[{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{"count":50,"covered":41}}},{"filename":"'"$foundation_root"'/Beta.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$darwin_root"'/Darwin.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$content_root"'/Content.swift","summary":{"lines":{"count":50,"covered":40}}}]}]}' \
    > "$temporary_root/conflicting-duplicate.json"
expect_fail_with_rule "conflicting-duplicate" "CC-COVERAGE-DUPLICATE-SOURCE" \
    --input "$temporary_root/conflicting-duplicate.json" \
    --source-root "$source_root" \
    --minimum 80

printf '%s\n' '{not-json' > "$temporary_root/malformed.json"
expect_fail_with_rule "malformed-json" "CC-COVERAGE-MALFORMED" \
    --input "$temporary_root/malformed.json" \
    --source-root "$source_root" \
    --minimum 80

printf '%s\n' '{"data":[]}' > "$temporary_root/empty-data.json"
expect_fail_with_rule "empty-data" "CC-COVERAGE-MALFORMED" \
    --input "$temporary_root/empty-data.json" \
    --source-root "$source_root" \
    --minimum 80

printf '%s\n' \
    '{"data":[{"files":[{"filename":"'"$foundation_root"'/Beta.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$darwin_root"'/Darwin.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$content_root"'/Content.swift","summary":{"lines":{"count":50,"covered":40}}}]}]}' \
    > "$temporary_root/missing-pure-evidence.json"
expect_fail_with_rule "missing-pure-evidence" "CC-COVERAGE-MISSING-SOURCE: CleanerCore" \
    --input "$temporary_root/missing-pure-evidence.json" \
    --source-root "$source_root" \
    --minimum 80

printf '%s\n' \
    '{"data":[{"files":[{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$darwin_root"'/Darwin.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$content_root"'/Content.swift","summary":{"lines":{"count":50,"covered":40}}}]}]}' \
    > "$temporary_root/missing-foundation-evidence.json"
expect_fail_with_rule \
    "missing-foundation-evidence" \
    "CC-COVERAGE-MISSING-SOURCE: CleanerCoreFoundation" \
    --input "$temporary_root/missing-foundation-evidence.json" \
    --source-root "$source_root" \
    --minimum 80

printf '%s\n' \
    '{"data":[{"files":[{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$foundation_root"'/Beta.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$content_root"'/Content.swift","summary":{"lines":{"count":50,"covered":40}}}]}]}' \
    > "$temporary_root/missing-darwin-evidence.json"
expect_fail_with_rule "missing-darwin-evidence" "CC-COVERAGE-MISSING-SOURCE: CleanerCoreDarwin" \
    --input "$temporary_root/missing-darwin-evidence.json" \
    --source-root "$source_root" \
    --minimum 80

printf '%s\n' \
    '{"data":[{"files":[{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$foundation_root"'/Beta.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$darwin_root"'/Darwin.swift","summary":{"lines":{"count":50,"covered":40}}}]}]}' \
    > "$temporary_root/missing-content-evidence.json"
expect_fail_with_rule \
    "missing-content-evidence" \
    "CC-COVERAGE-MISSING-SOURCE: CleanerCoreContentAdapter" \
    --input "$temporary_root/missing-content-evidence.json" \
    --source-root "$source_root" \
    --minimum 80

write_four_target_report "$temporary_root/zero-pure-lines.json" 0 0 50 40 50 40 50 40
expect_fail_with_rule "zero-pure-lines" "CC-COVERAGE-ZERO-LINES: CleanerCore" \
    --input "$temporary_root/zero-pure-lines.json" \
    --source-root "$source_root" \
    --minimum 80

write_four_target_report "$temporary_root/zero-foundation-lines.json" 50 40 0 0 50 40 50 40
expect_fail_with_rule "zero-foundation-lines" "CC-COVERAGE-ZERO-LINES: CleanerCoreFoundation" \
    --input "$temporary_root/zero-foundation-lines.json" \
    --source-root "$source_root" \
    --minimum 80

write_four_target_report "$temporary_root/zero-darwin-lines.json" 50 40 50 40 0 0 50 40
expect_fail_with_rule "zero-darwin-lines" "CC-COVERAGE-ZERO-LINES: CleanerCoreDarwin" \
    --input "$temporary_root/zero-darwin-lines.json" \
    --source-root "$source_root" \
    --minimum 80

write_four_target_report "$temporary_root/zero-content-lines.json" 50 40 50 40 50 40 0 0
expect_fail_with_rule "zero-content-lines" "CC-COVERAGE-ZERO-LINES: CleanerCoreContentAdapter" \
    --input "$temporary_root/zero-content-lines.json" \
    --source-root "$source_root" \
    --minimum 80

for invalid_case in nonnumeric negative covered-greater float boolean; do
    case "$invalid_case" in
        nonnumeric) invalid_lines='"count":"fifty","covered":40' ;;
        negative) invalid_lines='"count":50,"covered":-1' ;;
        covered-greater) invalid_lines='"count":50,"covered":51' ;;
        float) invalid_lines='"count":50.5,"covered":40' ;;
        boolean) invalid_lines='"count":true,"covered":40' ;;
    esac
    printf '%s\n' \
        '{"data":[{"files":[{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{'"$invalid_lines"'}}},{"filename":"'"$foundation_root"'/Beta.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$darwin_root"'/Darwin.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$content_root"'/Content.swift","summary":{"lines":{"count":50,"covered":40}}}]}]}' \
        > "$temporary_root/$invalid_case.json"
    expect_fail_with_rule "$invalid_case-counts" "CC-COVERAGE-LINE-COUNTS" \
        --input "$temporary_root/$invalid_case.json" \
        --source-root "$source_root" \
        --minimum 80
done

printf '%s\n' \
    '{"data":[{"files":[{"filename":"'"$pure_root"'/Alpha.swift","summary":{"lines":{"count":9223372036854775807,"covered":9223372036854775807}}},{"filename":"'"$foundation_root"'/Beta.swift","summary":{"lines":{"count":1,"covered":1}}},{"filename":"'"$darwin_root"'/Darwin.swift","summary":{"lines":{"count":1,"covered":1}}},{"filename":"'"$content_root"'/Content.swift","summary":{"lines":{"count":1,"covered":1}}}]}]}' \
    > "$temporary_root/overflow.json"
expect_fail_with_rule "overflow" "CC-COVERAGE-ARITHMETIC" \
    --input "$temporary_root/overflow.json" \
    --source-root "$source_root" \
    --minimum 80

expect_fail "zero-minimum" --input "$exact" --source-root "$source_root" --minimum 0
expect_fail "minimum-over-100" --input "$exact" --source-root "$source_root" --minimum 101
expect_fail "nonnumeric-minimum" --input "$exact" --source-root "$source_root" --minimum eighty
expect_fail "missing-input" \
    --input "$temporary_root/does-not-exist.json" \
    --source-root "$source_root" \
    --minimum 80
expect_fail "input-is-directory" \
    --input "$temporary_root" \
    --source-root "$source_root" \
    --minimum 80

ln -s "$exact" "$temporary_root/linked-coverage-input.json"
expect_fail_with_rule "coverage-input-symlink" "CC-COVERAGE-SYMLINK" \
    --input "$temporary_root/linked-coverage-input.json" \
    --source-root "$source_root" \
    --minimum 80
rm -f "$temporary_root/linked-coverage-input.json"

expect_fail "missing-source-root" \
    --input "$exact" \
    --source-root "$temporary_root/does-not-exist" \
    --minimum 80
expect_fail "unknown-argument" \
    --input "$exact" \
    --source-root "$source_root" \
    --threshold 80
expect_fail "duplicate-argument" \
    --input "$exact" \
    --input "$exact" \
    --minimum 80

empty_source_root="$temporary_root/Empty/CleanerCore/Sources"
mkdir -p \
    "$empty_source_root/CleanerCore" \
    "$empty_source_root/CleanerCoreFoundation" \
    "$empty_source_root/CleanerCoreDarwin" \
    "$empty_source_root/CleanerCoreContentAdapter"
expect_fail "empty-production-source" \
    --input "$exact" \
    --source-root "$empty_source_root" \
    --minimum 80

missing_target_root="$temporary_root/MissingTarget/CleanerCore/Sources"
mkdir -p \
    "$missing_target_root/CleanerCore" \
    "$missing_target_root/CleanerCoreFoundation" \
    "$missing_target_root/CleanerCoreDarwin"
touch \
    "$missing_target_root/CleanerCore/Only.swift" \
    "$missing_target_root/CleanerCoreFoundation/Foundation.swift" \
    "$missing_target_root/CleanerCoreDarwin/Darwin.swift"
expect_fail "missing-production-target" \
    --input "$exact" \
    --source-root "$missing_target_root" \
    --minimum 80

wrong_source_root="$temporary_root/WrongRoot/CleanerCore/Sources"
mkdir -p \
    "$wrong_source_root/CleanerCore" \
    "$wrong_source_root/CleanerCoreFoundation" \
    "$wrong_source_root/CleanerCoreDarwin" \
    "$wrong_source_root/CleanerCoreContentAdapter"
touch \
    "$wrong_source_root/CleanerCore/Core.swift" \
    "$wrong_source_root/CleanerCoreFoundation/Foundation.swift" \
    "$wrong_source_root/CleanerCoreDarwin/Darwin.swift" \
    "$wrong_source_root/CleanerCoreContentAdapter/Content.swift"
expect_fail_with_rule "mismatched-source-root" "CC-COVERAGE-MISSING-SOURCE: CleanerCore" \
    --input "$exact" \
    --source-root "$wrong_source_root" \
    --minimum 80

ln -s Alpha.swift "$pure_root/InsideLink.swift"
expect_fail_with_rule "inside-file-symlink" "CC-COVERAGE-SYMLINK" \
    --input "$exact" \
    --source-root "$source_root" \
    --minimum 80
rm -f "$pure_root/InsideLink.swift"

outside_source="$temporary_root/Outside.swift"
touch "$outside_source"
ln -s "$outside_source" "$pure_root/EscapingLink.swift"
expect_fail_with_rule "escaping-file-symlink" "CC-COVERAGE-SYMLINK" \
    --input "$exact" \
    --source-root "$source_root" \
    --minimum 80
rm -f "$pure_root/EscapingLink.swift"

ln -s "$pure_root/sub" "$foundation_root/LinkedDirectory"
expect_fail_with_rule "inside-directory-symlink" "CC-COVERAGE-SYMLINK" \
    --input "$exact" \
    --source-root "$source_root" \
    --minimum 80
rm -f "$foundation_root/LinkedDirectory"

ln -s "$outside_source" "$pure_root/Generated/.hidden-link"
expect_fail_with_rule "hidden-generated-symlink" "CC-COVERAGE-SYMLINK" \
    --input "$exact" \
    --source-root "$source_root" \
    --minimum 80
rm -f "$pure_root/Generated/.hidden-link"

linked_source_fixture="$temporary_root/LinkedSourceRoot/CleanerCore"
linked_source_actual="$temporary_root/LinkedSourceRoot/ActualSources"
mkdir -p \
    "$linked_source_fixture" \
    "$linked_source_actual/CleanerCore" \
    "$linked_source_actual/CleanerCoreFoundation" \
    "$linked_source_actual/CleanerCoreDarwin" \
    "$linked_source_actual/CleanerCoreContentAdapter"
touch \
    "$linked_source_actual/CleanerCore/Linked.swift" \
    "$linked_source_actual/CleanerCoreFoundation/Foundation.swift" \
    "$linked_source_actual/CleanerCoreDarwin/Darwin.swift" \
    "$linked_source_actual/CleanerCoreContentAdapter/Content.swift"
ln -s "$linked_source_actual" "$linked_source_fixture/Sources"
printf '%s\n' \
    '{"data":[{"files":[{"filename":"'"$linked_source_actual"'/CleanerCore/Linked.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$linked_source_actual"'/CleanerCoreFoundation/Foundation.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$linked_source_actual"'/CleanerCoreDarwin/Darwin.swift","summary":{"lines":{"count":50,"covered":40}}},{"filename":"'"$linked_source_actual"'/CleanerCoreContentAdapter/Content.swift","summary":{"lines":{"count":50,"covered":40}}}]}]}' \
    > "$temporary_root/linked-source-root.json"
expect_fail_with_rule "source-root-symlink" "CC-COVERAGE-SYMLINK" \
    --input "$temporary_root/linked-source-root.json" \
    --source-root "$linked_source_fixture/Sources" \
    --minimum 80

linked_target_fixture="$temporary_root/LinkedTarget/CleanerCore/Sources"
linked_target_actual="$temporary_root/LinkedTarget/ActualCleanerCore"
mkdir -p \
    "$linked_target_fixture" \
    "$linked_target_actual" \
    "$linked_target_fixture/CleanerCoreFoundation" \
    "$linked_target_fixture/CleanerCoreDarwin" \
    "$linked_target_fixture/CleanerCoreContentAdapter"
touch \
    "$linked_target_actual/Linked.swift" \
    "$linked_target_fixture/CleanerCoreFoundation/Foundation.swift" \
    "$linked_target_fixture/CleanerCoreDarwin/Darwin.swift" \
    "$linked_target_fixture/CleanerCoreContentAdapter/Content.swift"
ln -s "$linked_target_actual" "$linked_target_fixture/CleanerCore"
expect_fail_with_rule "production-target-root-symlink" "CC-COVERAGE-SYMLINK" \
    --input "$exact" \
    --source-root "$linked_target_fixture" \
    --minimum 80

[[ -f "$verifier" && -r "$verifier" ]] || {
    echo "Missing canonical CleanerCore verifier." >&2
    exit 1
}

orchestrator_root="$temporary_root/orchestrator"
mkdir -p "$orchestrator_root"
orchestrator_root=$(cd "$orchestrator_root" && pwd -P)
orchestrator_scripts="$orchestrator_root/scripts"
orchestrator_tests="$orchestrator_scripts/tests"
orchestrator_package="$orchestrator_root/CleanerCore"
orchestrator_developer="$orchestrator_root/Developer"
orchestrator_tools="$orchestrator_developer/usr/bin"
orchestrator_outside_tools="$orchestrator_root/outside-tools"
orchestrator_stage_log="$orchestrator_root/stages.log"
orchestrator_argument_log="$orchestrator_root/arguments.log"
orchestrator_environment_log="$orchestrator_root/environment.log"
fixture_sentinel="CLEANERCORE-GATE-SELF-TEST"
mkdir -p \
    "$orchestrator_tests" \
    "$orchestrator_package/Sources/CleanerCore" \
    "$orchestrator_package/Sources/CleanerCoreFoundation" \
    "$orchestrator_package/Sources/CleanerCoreDarwin" \
    "$orchestrator_package/Sources/CleanerCoreContentAdapter" \
    "$orchestrator_tools" \
    "$orchestrator_outside_tools"
cp "$verifier" "$orchestrator_scripts/verify-cleanercore.sh"
touch \
    "$orchestrator_package/Sources/CleanerCore/Core.swift" \
    "$orchestrator_package/Sources/CleanerCoreFoundation/Foundation.swift" \
    "$orchestrator_package/Sources/CleanerCoreDarwin/Darwin.swift" \
    "$orchestrator_package/Sources/CleanerCoreContentAdapter/Content.swift" \
    "$orchestrator_scripts/check-cleanercore-coverage.swift"

write_stage_stub() {
    local path="$1"
    local label="$2"

    printf '%s\n' \
        '#!/bin/bash' \
        'set -euo pipefail' \
        "printf '%s\\n' '$label' >> \"\${CC_GATE_STAGE_LOG:?}\"" \
        > "$path"
    chmod +x "$path"
}

write_stage_stub "$orchestrator_tests/verify-cleanercore-contract-tests.sh" "source-contract-self-tests"
write_stage_stub "$orchestrator_tests/run-cleanercore-tests-tests.sh" "runner-self-tests"
write_stage_stub "$orchestrator_tests/check-cleanercore-coverage-tests.sh" "coverage-parser-self-tests"
write_stage_stub "$orchestrator_scripts/verify-cleanercore-contract.sh" "source-contract"

# The single-quoted lines are emitted into isolated stub scripts and must expand there.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'printf "%s\n" "$*" > "${CC_GATE_ARGUMENT_LOG:?}"' \
    'printf "SWIFT_BIN=%s\nXCRUN_BIN=%s\nXCODE_SELECT_BIN=%s\n" "${SWIFT_BIN-<unset>}" "${XCRUN_BIN-<unset>}" "${XCODE_SELECT_BIN-<unset>}" > "${CC_GATE_ENVIRONMENT_LOG:?}"' \
    'scratch_path=""' \
    'filter=""' \
    'while [[ $# -gt 0 ]]; do' \
    '    if [[ "$1" == "--scratch-path" && $# -ge 2 ]]; then scratch_path="$2"; shift 2; elif [[ "$1" == "--filter" && $# -ge 2 ]]; then filter="$2"; shift 2; else shift; fi' \
    'done' \
    'if [[ -n "$filter" ]]; then printf "%s\n" "phase-filter:$filter" >> "${CC_GATE_STAGE_LOG:?}"; exit 0; fi' \
    'printf "%s\n" "swiftpm-tests-with-coverage" >> "${CC_GATE_STAGE_LOG:?}"' \
    '[[ -n "$scratch_path" ]] || exit 64' \
    '/bin/mkdir -p "$scratch_path"' \
    '/bin/sleep 1.1' \
    'if [[ "${CC_GATE_FAKE_PROFILE_MODE:-present}" != "missing" ]]; then' \
    '    /bin/mkdir -p "$scratch_path/fixture/debug/codecov"' \
    '    printf "%s\n" raw > "$scratch_path/fixture/debug/codecov/default.profraw"' \
    'fi' \
    'if [[ "${CC_GATE_FAKE_BUNDLE_MODE:-present}" != "missing" ]]; then' \
    '    test_binary="$scratch_path/fixture/debug/CleanerCorePackageTests.xctest/Contents/MacOS/CleanerCorePackageTests"' \
    '    /bin/mkdir -p "$(dirname "$test_binary")"' \
    '    printf "%s\n" binary > "$test_binary"' \
    '    /bin/chmod +x "$test_binary"' \
    '    if [[ "${CC_GATE_FAKE_BUNDLE_MODE:-present}" == "stale" ]]; then /usr/bin/touch -t 200001010000 "$test_binary"; fi' \
    'fi' \
    > "$orchestrator_scripts/run-cleanercore-tests.sh"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[[ "${1:-}" == "-p" ]] || exit 64' \
    'printf "%s\n" "${CC_GATE_FAKE_DEVELOPER_DIR:?}"' \
    > "$orchestrator_tools/xcode-select"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[[ "${1:-}" == "--find" ]] || exit 64' \
    'case "${2:-}" in' \
    '    llvm-profdata) printf "%s\n" "${CC_GATE_FAKE_TOOL_ROOT:?}/llvm-profdata" ;;' \
    '    llvm-cov) printf "%s\n" "${CC_GATE_FAKE_TOOL_ROOT:?}/llvm-cov" ;;' \
    '    *) exit 64 ;;' \
    'esac' \
    > "$orchestrator_tools/xcrun"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'printf "%s\n" "coverage-profile-merge" >> "${CC_GATE_STAGE_LOG:?}"' \
    'if [[ "${CC_GATE_FAKE_PROFDATA_MODE:-success}" == "failure" ]]; then exit 42; fi' \
    'output=""' \
    'while [[ $# -gt 0 ]]; do' \
    '    if [[ "$1" == "-o" && $# -ge 2 ]]; then output="$2"; shift 2; else shift; fi' \
    'done' \
    '[[ -n "$output" ]] || exit 64' \
    'printf "%s\n" profile > "$output"' \
    > "$orchestrator_tools/llvm-profdata"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'printf "%s\n" "coverage-export" >> "${CC_GATE_STAGE_LOG:?}"' \
    'case "${CC_GATE_FAKE_COV_MODE:-success}" in' \
    '    failure) exit 43 ;;' \
    '    empty) exit 0 ;;' \
    '    success) printf "%s\n" "{}" ;;' \
    '    *) exit 64 ;;' \
    'esac' \
    > "$orchestrator_tools/llvm-cov"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'printf "%s\n" "coverage-decision" >> "${CC_GATE_STAGE_LOG:?}"' \
    'printf "%s\n" "$*" >> "${CC_GATE_ARGUMENT_LOG:?}"' \
    'if [[ "${CC_GATE_FAKE_SWIFT_MODE:-success}" == "failure" ]]; then exit 44; fi' \
    'if [[ "${CC_GATE_FAKE_SWIFT_MODE:-success}" == "spoof" ]]; then printf "%s\n" "CLEANERCORE-GATE: PASS"; fi' \
    'printf "%s\n" "CLEANERCORE-COVERAGE: PASS aggregate 320/400 (80.00%)"' \
    'printf "%s\n" "CLEANERCORE-COVERAGE: CleanerCore 80/100 (80.00%)"' \
    'printf "%s\n" "CLEANERCORE-COVERAGE: CleanerCoreFoundation 80/100 (80.00%)"' \
    'printf "%s\n" "CLEANERCORE-COVERAGE: CleanerCoreDarwin 80/100 (80.00%)"' \
    'printf "%s\n" "CLEANERCORE-COVERAGE: CleanerCoreContentAdapter 80/100 (80.00%)"' \
    > "$orchestrator_tools/swift"

cp "$orchestrator_tools/llvm-profdata" "$orchestrator_outside_tools/llvm-profdata"
cp "$orchestrator_tools/llvm-cov" "$orchestrator_outside_tools/llvm-cov"

chmod +x \
    "$orchestrator_scripts/run-cleanercore-tests.sh" \
    "$orchestrator_scripts/verify-cleanercore.sh" \
    "$orchestrator_tools/xcode-select" \
    "$orchestrator_tools/xcrun" \
    "$orchestrator_tools/llvm-profdata" \
    "$orchestrator_tools/llvm-cov" \
    "$orchestrator_tools/swift" \
    "$orchestrator_outside_tools/llvm-profdata" \
    "$orchestrator_outside_tools/llvm-cov"

reset_orchestrator() {
    rm -rf "$orchestrator_package/.build"
    stale_binary="$orchestrator_package/.build/stale/debug/CleanerCorePackageTests.xctest/Contents/MacOS/CleanerCorePackageTests"
    mkdir -p "$(dirname "$stale_binary")" "$orchestrator_package/.build/stale/debug/codecov"
    printf '%s\n' binary > "$stale_binary"
    printf '%s\n' raw > "$orchestrator_package/.build/stale/debug/codecov/default.profraw"
    chmod +x "$stale_binary"
    touch -t 200001010000 "$stale_binary" "$orchestrator_package/.build/stale/debug/codecov/default.profraw"
    : > "$orchestrator_stage_log"
    : > "$orchestrator_argument_log"
    : > "$orchestrator_environment_log"
}

# Arguments are environment assignments forwarded to the fixture command by env.
# shellcheck disable=SC2120
run_orchestrator() {
    env \
        CC_GATE_STAGE_LOG="$orchestrator_stage_log" \
        CC_GATE_ARGUMENT_LOG="$orchestrator_argument_log" \
        CC_GATE_ENVIRONMENT_LOG="$orchestrator_environment_log" \
        CC_GATE_FAKE_DEVELOPER_DIR="$orchestrator_developer" \
        CC_GATE_FAKE_TOOL_ROOT="$orchestrator_tools" \
        CLEANERCORE_GATE_SELF_TEST_SENTINEL="$fixture_sentinel" \
        CLEANERCORE_FIXTURE_SWIFT_BIN="$orchestrator_tools/swift" \
        CLEANERCORE_FIXTURE_XCRUN_BIN="$orchestrator_tools/xcrun" \
        CLEANERCORE_FIXTURE_XCODE_SELECT_BIN="$orchestrator_tools/xcode-select" \
        "$@" \
        bash "$orchestrator_scripts/verify-cleanercore.sh" --fixture-tools
}

reset_orchestrator
expect_command_failure \
    "hostile normal-mode tool overrides" \
    "CC-GATE-TOOL-OVERRIDE" \
    env \
        SWIFT_BIN="$orchestrator_tools/swift" \
        XCRUN_BIN="$orchestrator_tools/xcrun" \
        XCODE_SELECT_BIN="$orchestrator_tools/xcode-select" \
        bash "$orchestrator_scripts/verify-cleanercore.sh"

reset_orchestrator
expect_command_failure \
    "fixture mode without sentinel" \
    "CC-GATE-FIXTURE-AUTHORIZATION" \
    env \
        CLEANERCORE_FIXTURE_SWIFT_BIN="$orchestrator_tools/swift" \
        CLEANERCORE_FIXTURE_XCRUN_BIN="$orchestrator_tools/xcrun" \
        CLEANERCORE_FIXTURE_XCODE_SELECT_BIN="$orchestrator_tools/xcode-select" \
        bash "$orchestrator_scripts/verify-cleanercore.sh" --fixture-tools

reset_orchestrator
expect_command_failure \
    "missing fixture Swift tool" \
    "CC-GATE-SWIFT-TOOL" \
    run_orchestrator CLEANERCORE_FIXTURE_SWIFT_BIN="$orchestrator_tools/missing-swift"

reset_orchestrator
expect_command_failure \
    "missing fixture xcrun tool" \
    "CC-GATE-XCRUN-TOOL" \
    run_orchestrator CLEANERCORE_FIXTURE_XCRUN_BIN="$orchestrator_tools/missing-xcrun"

reset_orchestrator
expect_command_failure \
    "missing fixture xcode-select tool" \
    "CC-GATE-XCODE-SELECT-TOOL" \
    run_orchestrator CLEANERCORE_FIXTURE_XCODE_SELECT_BIN="$orchestrator_tools/missing-xcode-select"

reset_orchestrator
expect_command_failure \
    "LLVM tool outside selected developer directory" \
    "CC-GATE-LLVM-TRUST" \
    run_orchestrator CC_GATE_FAKE_TOOL_ROOT="$orchestrator_outside_tools"

reset_orchestrator
expect_command_failure \
    "missing raw profile" \
    "CC-GATE-COVERAGE-PROFILE" \
    run_orchestrator CC_GATE_FAKE_PROFILE_MODE=missing

reset_orchestrator
expect_command_failure \
    "missing test bundle" \
    "CC-GATE-TEST-BINARY" \
    run_orchestrator CC_GATE_FAKE_BUNDLE_MODE=missing

reset_orchestrator
expect_command_failure \
    "stale test bundle" \
    "CC-GATE-TEST-BINARY" \
    run_orchestrator CC_GATE_FAKE_BUNDLE_MODE=stale

reset_orchestrator
expect_command_failure \
    "profile merge failure" \
    "CC-GATE-COVERAGE-PROFILE" \
    run_orchestrator CC_GATE_FAKE_PROFDATA_MODE=failure

reset_orchestrator
expect_command_failure \
    "coverage export failure" \
    "CC-GATE-COVERAGE-EXPORT" \
    run_orchestrator CC_GATE_FAKE_COV_MODE=failure

reset_orchestrator
expect_command_failure \
    "empty coverage export" \
    "CC-GATE-COVERAGE-EXPORT" \
    run_orchestrator CC_GATE_FAKE_COV_MODE=empty

reset_orchestrator
expect_command_failure \
    "coverage parser failure" \
    "CC-GATE-COVERAGE-DECISION" \
    run_orchestrator CC_GATE_FAKE_SWIFT_MODE=failure

reset_orchestrator
# shellcheck disable=SC2119
run_orchestrator > "$temporary_root/orchestrator-success.out"

expected_stages=$'source-contract-self-tests\nrunner-self-tests\ncoverage-parser-self-tests\nsource-contract\nphase-filter:PolicyDispositionTests|PolicyRankingTests|CapabilityCardTests\nphase-filter:CleanupPlanTests|ApprovalBindingTests\nphase-filter:PolicyGoldenTests|PlanInvalidationPropertyTests\nphase-filter:TrashOperationAuthorityTests\nphase-filter:TrashRevalidationTests\nphase-filter:TrashExecutionTests\nphase-filter:FoundationTrashAdapterTests\nphase-filter:TrashExecutionHostileFixtureTests\nphase-filter:ReceiptTransitionTests|ReceiptStoreAdapterTests|ReceiptCoordinatorTests|ReceiptReconciliationTests|ReceiptPrivacyTests|ReceiptRetentionTests|ReceiptHistoryDeletionTests|ReceiptRecoveryTests|ReceiptHostileFixtureTests\nphase-filter:HuggingFaceInventoryTests\nphase-filter:HuggingFaceHostileFixtureTests|ModelStoreAuthorityTests\nphase-filter:OllamaInventoryTests\nphase-filter:SelectedModelRootTests|ModelStoreAuthorityTests\nphase-filter:AIModelHostileFixtureTests\nphase-filter:ModelStoreAuthorityTests|AIModelHostileFixtureTests\nswiftpm-tests-with-coverage\ncoverage-profile-merge\ncoverage-export\ncoverage-decision\ncoverage-decision\ncoverage-decision'
if [[ $(< "$orchestrator_stage_log") != "$expected_stages" ]]; then
    echo "Canonical CleanerCore stages are missing or out of order." >&2
    exit 1
fi

runner_arguments=$(head -n 1 "$orchestrator_argument_log")
if [[ ! "$runner_arguments" =~ ^--enable-code-coverage\ --no-parallel\ --scratch-path\ /.+/swiftpm-scratch$ ]]; then
    echo "Canonical CleanerCore runner flags are incomplete." >&2
    exit 1
fi
if ! grep -Fq -- '--source-root '"$orchestrator_package"'/Sources --minimum 80' "$orchestrator_argument_log"; then
    echo "Canonical CleanerCore parser invocation is incomplete." >&2
    exit 1
fi
if [[ $(/usr/bin/grep -Fc -- '--source-root '"$orchestrator_package"'/Sources --minimum 80' "$orchestrator_argument_log") -lt 3 ]]; then
    echo "Canonical CleanerCore coverage parser was not invoked three times." >&2
    exit 1
fi
if [[ $(< "$orchestrator_environment_log") != $'SWIFT_BIN=<unset>\nXCRUN_BIN=<unset>\nXCODE_SELECT_BIN=<unset>' ]]; then
    echo "Canonical CleanerCore runner inherited forbidden tool overrides." >&2
    exit 1
fi
if ! grep -Fxq 'CLEANERCORE-GATE: FIXTURE PASS' "$temporary_root/orchestrator-success.out"; then
    echo "Fixture CleanerCore verifier did not report fixture-only success." >&2
    exit 1
fi
if grep -Fxq 'CLEANERCORE-GATE: PASS' "$temporary_root/orchestrator-success.out"; then
    echo "Fixture CleanerCore verifier emitted a canonical pass." >&2
    exit 1
fi

reset_orchestrator
run_orchestrator CC_GATE_FAKE_SWIFT_MODE=spoof > "$temporary_root/orchestrator-spoof.out"
if ! grep -Fxq 'CLEANERCORE-GATE: FIXTURE PASS' "$temporary_root/orchestrator-spoof.out"; then
    echo "Spoof fixture did not reach fixture-only success." >&2
    exit 1
fi
if grep -Fxq 'CLEANERCORE-GATE: PASS' "$temporary_root/orchestrator-spoof.out"; then
    echo "Fixture tool output escaped as a canonical pass." >&2
    exit 1
fi

expect_command_failure \
    "canonical verifier arguments" \
    "CC-GATE-ARGUMENTS" \
    bash "$orchestrator_scripts/verify-cleanercore.sh" unexpected

echo "CleanerCore coverage parser self-tests passed."
