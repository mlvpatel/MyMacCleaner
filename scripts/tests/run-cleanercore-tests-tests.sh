#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd -P)
runner="$repo_root/scripts/run-cleanercore-tests.sh"
temporary_directory=""

cleanup() {
    if [[ -n "$temporary_directory" ]]; then
        /bin/rm -rf "$temporary_directory"
    fi
}

trap cleanup EXIT

temporary_directory=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mymaccleaner-cleanercore-runner.XXXXXX")
fake_swift="$temporary_directory/fake-swift"
fake_xcode_select="$temporary_directory/fake-xcode-select"
argument_log="$temporary_directory/arguments.log"
environment_log="$temporary_directory/environment.log"

cat > "$fake_xcode_select" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "-p" ]]; then
    printf '%s\n' "/tmp/mymaccleaner-fake-developer"
    exit 0
fi
exit 64
EOF

cat > "$fake_swift" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" > "${MYMACCLEANER_RUNNER_ARGUMENT_LOG:?}"
printf 'CLANG=%s\nSWIFTPM=%s\n' "${CLANG_MODULE_CACHE_PATH:-}" "${SWIFTPM_MODULECACHE_OVERRIDE:-}" > "${MYMACCLEANER_RUNNER_ENVIRONMENT_LOG:?}"
case "${MYMACCLEANER_FAKE_SWIFT_MODE:-success}" in
    success)
        printf '%s\n' 'Test run with 7 tests in 2 suites passed after 0.001 seconds.'
        ;;
    filtered)
        printf '%s\n' 'Suite "CleanerCore Tracer Scan" passed after 0.001 seconds.'
        printf '%s\n' 'Test run with 1 test in 1 suite passed after 0.001 seconds.'
        ;;
    zero)
        printf '%s\n' 'Test run with 0 tests in 0 suites passed after 0.001 seconds.'
        ;;
    failure)
        printf '%s\n' 'SwiftPM failed before executing tests.'
        exit 42
        ;;
    malformed)
        printf '%s\n' 'Build complete.'
        ;;
    *)
        exit 65
        ;;
esac
EOF

/bin/chmod +x "$fake_swift" "$fake_xcode_select"

run_runner() {
    SWIFT_BIN="$fake_swift" \
        XCODE_SELECT_BIN="$fake_xcode_select" \
        MYMACCLEANER_RUNNER_ARGUMENT_LOG="$argument_log" \
        MYMACCLEANER_RUNNER_ENVIRONMENT_LOG="$environment_log" \
        "$runner" "$@"
}

expect_success() {
    local label="$1"
    shift

    if "$@" > "$temporary_directory/$label.out" 2>&1; then
        return 0
    fi

    /bin/cat "$temporary_directory/$label.out" >&2
    echo "Expected success: $label" >&2
    exit 1
}

expect_failure() {
    local label="$1"
    local expected="$2"
    shift 2

    local output
    set +e
    output=$("$@" 2>&1)
    local status=$?
    set -e

    if [[ "$status" -eq 0 ]]; then
        echo "Expected failure: $label" >&2
        exit 1
    fi

    if [[ "$expected" != "__ANY__" && "$output" != *"$expected"* ]]; then
        echo "Expected $expected for $label" >&2
        exit 1
    fi
}

expect_status() {
    local label="$1"
    local expected_status="$2"
    shift 2

    set +e
    "$@" > "$temporary_directory/$label.out" 2>&1
    local status=$?
    set -e

    if [[ "$status" -ne "$expected_status" ]]; then
        echo "Expected status $expected_status for $label, got $status" >&2
        exit 1
    fi
}

expect_success "positive" run_runner
/usr/bin/grep -Fq -- 'test --package-path CleanerCore --no-parallel' "$argument_log"

expect_success "explicit serial" run_runner --no-parallel
/usr/bin/grep -Fq -- '--no-parallel' "$argument_log"

MYMACCLEANER_FAKE_SWIFT_MODE=filtered expect_success "forwarded" run_runner --parallel --enable-code-coverage --filter CleanerCoreTests.TracerScanTests
/usr/bin/grep -Fq -- '--parallel --enable-code-coverage --filter CleanerCoreTests.TracerScanTests' "$argument_log"

scratch_path="$temporary_directory/isolated-scratch"
expect_success "scratch path" run_runner --scratch-path "$scratch_path"
/usr/bin/grep -Fq -- "--scratch-path $scratch_path" "$argument_log"

CODEX_SANDBOX=1 expect_success "sandbox" run_runner
/usr/bin/grep -Eq '^CLANG=.+mymaccleaner-cleanercore-cache/clang-module-cache$' "$environment_log"
/usr/bin/grep -Eq '^SWIFTPM=.+mymaccleaner-cleanercore-cache/swiftpm-module-cache$' "$environment_log"

MYMACCLEANER_FAKE_SWIFT_MODE=filtered expect_success "filtered" run_runner --filter CleanerCoreTests.TracerScanTests

MYMACCLEANER_FAKE_SWIFT_MODE=zero expect_failure "zero tests" "selected zero tests" run_runner
MYMACCLEANER_FAKE_SWIFT_MODE=malformed expect_failure "malformed output" "selected zero tests" run_runner
MYMACCLEANER_FAKE_SWIFT_MODE=failure expect_status "swift failure" 42 run_runner

expect_failure "unknown argument" "unsupported argument" run_runner --configuration debug
expect_failure "duplicate parallel mode" "accepts a parallelization mode only once" run_runner --parallel --no-parallel
expect_failure "empty filter" "requires a non-empty --filter value" run_runner --filter
expect_failure "empty scratch path" "requires a non-empty --scratch-path value" run_runner --scratch-path
expect_failure "option as scratch path" "requires a non-empty --scratch-path value" run_runner --scratch-path --parallel
expect_failure "relative scratch path" "requires an absolute --scratch-path value" run_runner --scratch-path relative/build
expect_failure "parent traversal scratch path" "must not contain parent traversal" run_runner --scratch-path "$temporary_directory/../escaped-build"
expect_failure "duplicate scratch path" "accepts --scratch-path only once" run_runner --scratch-path "$scratch_path" --scratch-path "$scratch_path/second"

echo "CleanerCore runner self-tests passed."
