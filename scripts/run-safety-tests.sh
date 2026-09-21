#!/bin/bash

set -euo pipefail

developer_dir=$(/usr/bin/xcode-select -p)
framework_candidates=(
    "$developer_dir/Library/Developer/Frameworks"
    "$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks"
)
library_candidates=(
    "$developer_dir/Library/Developer/usr/lib"
    "$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/lib"
)

swiftpm_arguments=(test --package-path SafetyContract)
selected_filter=""

capture_filter_argument() {
    local previous=""
    local argument

    for argument in "$@"; do
        if [[ "$previous" == "--filter" ]]; then
            selected_filter="$argument"
            return
        fi
        previous="$argument"
    done
}

suite_title_for_filter() {
    local expected="$1"

    case "$expected" in
        *RedactionTests*) printf '%s\n' 'Redacting Diagnostic Contract' ;;
        *NetworkDeniedTests*) printf '%s\n' 'Denied Network Contract' ;;
        *SourceContractTests*) printf '%s\n' 'Source Contract' ;;
        *DisabledOperationPresentationTests*) printf '%s\n' 'Disabled Operation Presentation Contract' ;;
        *) printf '%s\n' '' ;;
    esac
}

capture_filter_argument "$@"

if [[ -n "${CODEX_SANDBOX:-}" ]]; then
    cache_root="${TMPDIR:-/tmp}/mymaccleaner-safety-contract-cache"
    mkdir -p "$cache_root"
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

output_file=$(mktemp "${TMPDIR:-/tmp}/mymaccleaner-safety-tests.XXXXXX")
trap 'rm -f "$output_file"' EXIT

echo "Running SafetyContract tests with /usr/bin/swift"
echo "Selected developer directory: $developer_dir"

set +e
/usr/bin/swift "${swiftpm_arguments[@]}" "$@" 2>&1 | tee "$output_file"
swift_status=${PIPESTATUS[0]}
set -e

if (( swift_status != 0 )); then
    exit "$swift_status"
fi

if ! /usr/bin/grep -Eq 'Test run with [1-9][0-9]* tests?' "$output_file"; then
    echo "SafetyContract test runner selected zero tests or did not report a test run." >&2
    exit 1
fi

if [[ -n "$selected_filter" ]]; then
    IFS='|' read -r -a expected_filters <<< "$selected_filter"
    for expected_filter in "${expected_filters[@]}"; do
        suite_title=$(suite_title_for_filter "$expected_filter")
        if [[ -n "$suite_title" ]] && ! /usr/bin/grep -Fq "Suite \"$suite_title\" passed" "$output_file"; then
            echo "SafetyContract filter did not run expected suite: $expected_filter" >&2
            exit 1
        fi
    done
fi
