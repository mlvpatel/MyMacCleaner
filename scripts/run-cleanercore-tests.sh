#!/bin/bash

set -euo pipefail

swift_bin="${SWIFT_BIN:-/usr/bin/swift}"
xcode_select_bin="${XCODE_SELECT_BIN:-/usr/bin/xcode-select}"
developer_dir=$("$xcode_select_bin" -p)
framework_candidates=(
    "$developer_dir/Library/Developer/Frameworks"
    "$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks"
)
library_candidates=(
    "$developer_dir/Library/Developer/usr/lib"
    "$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/lib"
)

swiftpm_arguments=(test --package-path CleanerCore --no-parallel)
parallelization_mode_seen=0
selected_filter=""
selected_scratch_path=""

parse_arguments() {
    local argument

    while [[ $# -gt 0 ]]; do
        argument="$1"
        case "$argument" in
            --filter)
                [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || {
                    echo "CleanerCore test runner requires a non-empty --filter value." >&2
                    exit 64
                }
                selected_filter="$2"
                swiftpm_arguments+=(--filter "$2")
                shift 2
                ;;
            --parallel|--no-parallel)
                (( parallelization_mode_seen == 0 )) || {
                    echo "CleanerCore test runner accepts a parallelization mode only once." >&2
                    exit 64
                }
                swiftpm_arguments[3]="$argument"
                parallelization_mode_seen=1
                shift
                ;;
            --enable-code-coverage)
                swiftpm_arguments+=("$argument")
                shift
                ;;
            --scratch-path)
                [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || {
                    echo "CleanerCore test runner requires a non-empty --scratch-path value." >&2
                    exit 64
                }
                [[ -z "$selected_scratch_path" ]] || {
                    echo "CleanerCore test runner accepts --scratch-path only once." >&2
                    exit 64
                }
                [[ "$2" == /* ]] || {
                    echo "CleanerCore test runner requires an absolute --scratch-path value." >&2
                    exit 64
                }
                [[ "$2" != *"/../"* && "$2" != */.. ]] || {
                    echo "CleanerCore test runner scratch path must not contain parent traversal." >&2
                    exit 64
                }
                selected_scratch_path="$2"
                swiftpm_arguments+=(--scratch-path "$2")
                shift 2
                ;;
            *)
                echo "CleanerCore test runner received unsupported argument: $argument" >&2
                exit 64
                ;;
        esac
    done
}

suite_title_for_filter() {
    local expected="$1"

    case "$expected" in
        *TracerScanTests*) printf '%s\n' 'CleanerCore Tracer Scan' ;;
        *ReceiptTransitionTests*) printf '%s\n' 'Receipt Transition Tests' ;;
        *ReceiptPrivacyTests*) printf '%s\n' 'Receipt Privacy Tests' ;;
        *ReceiptReconciliationTests*) printf '%s\n' 'Receipt Reconciliation Tests' ;;
        *ReceiptStoreAdapterTests*) printf '%s\n' 'Receipt Store Adapter Tests' ;;
        *ReceiptCoordinatorTests*) printf '%s\n' 'Receipt Coordinator Tests' ;;
        *ReceiptRetentionTests*) printf '%s\n' 'Receipt Retention Tests' ;;
        *ReceiptHistoryDeletionTests*) printf '%s\n' 'Receipt History Deletion Tests' ;;
        *ReceiptRecoveryTests*) printf '%s\n' 'Receipt Recovery Tests' ;;
        *ReceiptHostileFixtureTests*) printf '%s\n' 'Receipt Hostile Fixture Tests' ;;
        *ReceiptStoreHostileFixtureTests*) printf '%s\n' 'Receipt Store Hostile Fixture Tests' ;;
        *AdaptiveExperienceProjectionTests*) printf '%s\n' 'Adaptive Experience Projection' ;;
        *DeveloperInventoryContractTests*) printf '%s\n' 'Developer Inventory Contract' ;;
        *DeveloperInventoryAdapterTests*) printf '%s\n' 'Developer Inventory Adapter' ;;
        *DockerDiskUsageAdapterTests*) printf '%s\n' 'Docker Disk Usage Adapter' ;;
        *) printf '%s\n' '' ;;
    esac
}

parse_arguments "$@"

if [[ -n "${CODEX_SANDBOX:-}" ]]; then
    cache_root="${TMPDIR:-/tmp}/mymaccleaner-cleanercore-cache"
    /bin/mkdir -p "$cache_root"
    export CLANG_MODULE_CACHE_PATH="$cache_root/clang-module-cache"
    export SWIFTPM_MODULECACHE_OVERRIDE="$cache_root/swiftpm-module-cache"
    swiftpm_arguments+=(--disable-sandbox)
fi

for framework_directory in "${framework_candidates[@]}"; do
    if [[ -d "$framework_directory/Testing.framework" ]]; then
        swiftpm_arguments+=(
            -Xswiftc -F -Xswiftc "$framework_directory"
            -Xlinker -F -Xlinker "$framework_directory"
            -Xlinker -framework -Xlinker Testing
            -Xlinker -rpath -Xlinker "$framework_directory"
        )
        break
    fi
done

for library_directory in "${library_candidates[@]}"; do
    if [[ -f "$library_directory/lib_TestingInterop.dylib" ]]; then
        swiftpm_arguments+=(-Xlinker -rpath -Xlinker "$library_directory")
        break
    fi
done

output_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/mymaccleaner-cleanercore-tests.XXXXXX")
trap '/bin/rm -f "$output_file"' EXIT

echo "Running CleanerCore tests with $swift_bin"
echo "Selected developer directory: $developer_dir"

set +e
"$swift_bin" "${swiftpm_arguments[@]}" 2>&1 | /usr/bin/tee "$output_file"
swift_status=${PIPESTATUS[0]}
set -e

if (( swift_status != 0 )); then
    exit "$swift_status"
fi

if ! /usr/bin/grep -Eq 'Test run with [1-9][0-9]* tests?' "$output_file"; then
    echo "CleanerCore test runner selected zero tests or did not report a test run." >&2
    exit 1
fi

if [[ -n "$selected_filter" ]]; then
    IFS='|' read -r -a expected_filters <<< "$selected_filter"
    for expected_filter in "${expected_filters[@]}"; do
        suite_title=$(suite_title_for_filter "$expected_filter")
        if [[ -n "$suite_title" ]] && ! /usr/bin/grep -Fq "Suite \"$suite_title\" passed" "$output_file"; then
            echo "CleanerCore filter did not run expected suite: $expected_filter" >&2
            exit 1
        fi
    done
fi
