#!/bin/bash

set -euo pipefail

readonly self_test_sentinel="CLEANERCORE-CONTRACT-SELF-TEST"
readonly script_directory=$(cd "$(dirname "$0")" && pwd -P)
readonly repository_root=$(cd "$script_directory/.." && pwd -P)
readonly fixture_root="$repository_root/scripts/tests/fixtures/cleanercore-contract"
readonly package_root="$repository_root/CleanerCore"

fail() {
    local rule_id="$1"
    local location="${2:-}"

    if [[ -n "$location" ]]; then
        printf '%s: %s\n' "$rule_id" "$location" >&2
    else
        printf '%s\n' "$rule_id" >&2
    fi
    exit 1
}

canonical_path() {
    local candidate="$1"

    if [[ -d "$candidate" ]]; then
        (cd "$candidate" && pwd -P)
    elif [[ -f "$candidate" ]]; then
        local parent
        parent=$(cd "$(dirname "$candidate")" && pwd -P)
        printf '%s/%s\n' "$parent" "$(basename "$candidate")"
    else
        return 1
    fi
}

validate_fixture_file() {
    local candidate="$1"
    local expected_parent="$2"
    local canonical

    canonical=$(canonical_path "$candidate" || true)
    [[ -n "$canonical" && -f "$canonical" && -r "$canonical" ]] || fail "CC-INVALID-ROOT"
    case "$canonical" in
        "$expected_parent"/*) ;;
        *) fail "CC-ROOT-ESCAPE" "$(location_for "$canonical")" ;;
    esac
    printf '%s\n' "$canonical"
}

location_for() {
    local path="$1"

    if [[ "$path" == "$repository_root/"* ]]; then
        printf '%s\n' "${path#"$repository_root/"}"
    else
        printf '%s\n' "${path##*/}"
    fi
}

first_match_line() {
    local pattern="$1"
    local file="$2"

    /usr/bin/grep -nE -- "$pattern" "$file" | /usr/bin/head -n 1 | /usr/bin/cut -d: -f1
}

first_diagnostic_payload_line() {
    local file="$1"

    /usr/bin/awk '
        /enum[[:space:]]+ScanDiagnosticEvent/ { in_diagnostic_event = 1 }
        in_diagnostic_event && /case[[:space:]].*\((ScanOutcome|ScanIssue|DeclaredRootID|DetectorID|RelativeLocator|String)\)/ {
            print NR
            exit
        }
        in_diagnostic_event && /^[[:space:]]*}/ { in_diagnostic_event = 0 }
    ' "$file"
}

report_match() {
    local rule_id="$1"
    local file="$2"
    local line_number="$3"

    fail "$rule_id" "$(location_for "$file"):$line_number"
}

is_fixture_authorized() {
    [[ "${CLEANERCORE_CONTRACT_SELF_TEST_SENTINEL:-}" == "$self_test_sentinel" ]]
}

validate_root() {
    local candidate="$1"
    local expected_parent="$2"
    local canonical

    canonical=$(canonical_path "$candidate" || true)
    [[ -n "$canonical" && -d "$canonical" && -r "$canonical" ]] || fail "CC-INVALID-ROOT"

    case "$canonical" in
        "$expected_parent"|"$expected_parent"/*)
            ;;
        *)
            fail "CC-ROOT-ESCAPE" "$(location_for "$canonical")"
            ;;
    esac

    printf '%s\n' "$canonical"
}

scan_common_source_file() {
    local file="$1"
    local line_number

    line_number=$(first_match_line 'import[[:space:]]+(SwiftUI|AppKit|UIKit|WebKit|Sparkle|Network|CloudKit)|canImport[[:space:]]*\([[:space:]]*(SwiftUI|AppKit|Sparkle|Network|CloudKit)[[:space:]]*\)' "$file" || true)
    if [[ -n "$line_number" ]]; then
        if [[ "$(basename "$file")" == "FinderReceiptRevealAdapter.swift" ]] \
            && ! /usr/bin/grep -Eq 'import[[:space:]]+(SwiftUI|UIKit|WebKit|Sparkle|Network|CloudKit)|canImport[[:space:]]*\([[:space:]]*(SwiftUI|Sparkle|Network|CloudKit)[[:space:]]*\)' "$file"; then
            :
        else
            report_match "CC-FORBIDDEN-IMPORT" "$file" "$line_number"
        fi
    fi

    line_number=$(first_match_line 'URLSession|URLRequest|NSURLSession|NW(Connection|Listener|PathMonitor)|https?://' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-NETWORK-CAPABILITY" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'Process[[:space:]]*\(|posix_spawn|system[[:space:]]*\(|NSTask|/bin/(sh|bash|zsh)|/usr/bin/(osascript|open)|shell' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PROCESS-CAPABILITY" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'NSAppleScript|Authorization(Create|Execute)|with administrator privileges|SMAppService|ServiceManagement' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-ELEVATION-CAPABILITY" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'removeItem[[:space:]]*\(|trashItem[[:space:]]*\(|replaceItemAt|createFile[[:space:]]*\(|FileHandle[^(]*forWriting|write[[:space:]]*\(' "$file" || true)
    if [[ -n "$line_number" ]]; then
        local base
        base="$(basename "$file")"
        if [[ "$base" == "FoundationTrashAdapter.swift" ]]; then
            :
        elif [[ "$base" == "DarwinReceiptLease.swift" ]] && /usr/bin/grep -Eq 'write[[:space:]]*\(' "$file" && ! /usr/bin/grep -Eq 'removeItem[[:space:]]*\(|trashItem[[:space:]]*\(' "$file"; then
            :
        elif [[ "$base" == "AppSupportReceiptStore.swift" ]] && /usr/bin/grep -Eq 'removeItem' "$file" && ! /usr/bin/grep -Eq 'trashItem[[:space:]]*\(' "$file"; then
            :
        else
            report_match "CC-MUTATION-CAPABILITY" "$file" "$line_number"
        fi
    fi

    line_number=$(first_match_line 'dlopen|dlsym|NSClassFromString|Bundle[.]main|Bundle[[:space:]]*\(|plugin|PlugIn|DetectorRegistry[^(]*from|JSONDecoder[[:space:]]*\(' "$file" || true)
    if [[ -n "$line_number" ]]; then
        if [[ "$(basename "$file")" != "AppSupportReceiptStore.swift" ]]; then
            report_match "CC-DYNAMIC-REGISTRY" "$file" "$line_number"
        fi
    fi

    line_number=$(first_match_line 'catch[[:space:]]*\{[[:space:]]*\}|try[?][[:space:]]' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-SILENT-ERROR" "$file" "$line_number"
    fi

    line_number=$(first_diagnostic_payload_line "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-DIAGNOSTIC-PAYLOAD" "$file" "$line_number"
    fi
}

scan_pure_source_file() {
    local file="$1"
    local line_number

    scan_common_source_file "$file"

    line_number=$(first_match_line '^import[[:space:]]+CryptoKit$' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-CONTENT-CRYPTOKIT-OWNER" "$file" "$line_number"
    fi

    line_number=$(first_match_line '^import[[:space:]]+' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PURE-IMPORT" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'FileManager|URL[[:space:]]*\(|URL[.]|Date[[:space:]]*\(|Date[.]now|Dispatch(Time|Queue)|Task[.]sleep|UUID[[:space:]]*\(|[.]shared' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-AMBIENT-AUTHORITY" "$file" "$line_number"
    fi
}

scan_foundation_source_file() {
    local file="$1"
    local line_number

    scan_common_source_file "$file"

    if [[ "$(basename "$file")" == "StreamingContentEvidenceAdapter.swift" ]]; then
        report_match "CC-CONTENT-UNSELECTED-BRANCH" "$file" "1"
    fi

    while IFS= read -r line; do
        case "$line" in
            "import Foundation"|"import CleanerCore")
                ;;
            "import CryptoKit")
                if [[ "$(basename "$file")" != "CryptoKitPlanDigestAdapter.swift" ]]; then
                    line_number=$(first_match_line "^${line}$" "$file" || true)
                    report_match "CC-FOUNDATION-IMPORT" "$file" "${line_number:-1}"
                fi
                ;;
            "import Darwin")
                if [[ "$(basename "$file")" != "DarwinReceiptLease.swift" ]]; then
                    line_number=$(first_match_line "^${line}$" "$file" || true)
                    report_match "CC-FOUNDATION-IMPORT" "$file" "${line_number:-1}"
                fi
                ;;
            "import AppKit")
                if [[ "$(basename "$file")" != "FinderReceiptRevealAdapter.swift" ]]; then
                    line_number=$(first_match_line "^${line}$" "$file" || true)
                    report_match "CC-FOUNDATION-IMPORT" "$file" "${line_number:-1}"
                fi
                ;;
            import*)
                line_number=$(first_match_line "^${line}$" "$file" || true)
                report_match "CC-FOUNDATION-IMPORT" "$file" "${line_number:-1}"
                ;;
        esac
    done < <(/usr/bin/grep -E '^import[[:space:]]+' "$file" || true)

    line_number=$(first_match_line 'FileManager[.]default|Date[.]now|URLSession|Process[[:space:]]*\(' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-FOUNDATION-AMBIENT" "$file" "$line_number"
    fi

    if [[ "$(basename "$file")" == "FoundationTrashAdapter.swift" ]]; then
        local trash_count
        trash_count=$(/usr/bin/grep -c 'trashItem[[:space:]]*(' "$file" || true)
        if [[ "$trash_count" -ne 1 ]]; then
            line_number=$(first_match_line 'trashItem[[:space:]]*(' "$file" || true)
            report_match "CC-PHASE6-SOLE-CALL" "$file" "${line_number:-1}"
        fi
    fi

    if [[ "$(basename "$file")" == "FinderReceiptRevealAdapter.swift" ]]; then
        local reveal_count
        reveal_count=$(/usr/bin/grep -c 'activateFileViewerSelecting' "$file" || true)
        if [[ "$reveal_count" -ne 1 ]]; then
            line_number=$(first_match_line 'activateFileViewerSelecting' "$file" || true)
            report_match "CC-FINDER-REVEAL-OWNER" "$file" "${line_number:-1}"
        fi
    fi
}

scan_darwin_source_file() {
    local file="$1"
    local line_number

    scan_common_source_file "$file"
    while IFS= read -r line; do
        case "$line" in
            "import CleanerCore"|"import Darwin"|"import Dispatch"|"import Foundation") ;;
            import*)
                line_number=$(first_match_line "^${line}$" "$file" || true)
                report_match "CC-DARWIN-IMPORT" "$file" "${line_number:-1}"
                ;;
        esac
    done < <(/usr/bin/grep -E '^import[[:space:]]+' "$file" || true)

    line_number=$(first_match_line 'proc_(terminate|set|signal|suspend|resume)|(^|[^[:alnum:]_])(kill|killpg|setpriority|task_for_pid|mach_vm_[[:alnum:]_]*|vm_purg[[:alnum:]_]*|purge)[[:space:]]*\(' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-DARWIN-CONTROL-CAPABILITY" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'arguments|environment|currentDirectory|proc_pidpath|proc_regionfilename|pbi_uid|pbi_ruid|prompt|repository|model|username|userName|openFiles|executablePath' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-DARWIN-SENSITIVE-METADATA" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'FileManager|FileHandle|Data[[:space:]]*\([[:space:]]*contentsOf|String[[:space:]]*\([[:space:]]*contentsOf|URL[[:space:]]*\([[:space:]]*fileURLWithPath|(^|[^[:alnum:]_])(open|fopen|freopen|stat|lstat|readlink|unlink|rename|mkdir|rmdir|chmod|chown|access)[[:space:]]*\(' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-DARWIN-FILESYSTEM-CAPABILITY" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'UserDefaults|NSUserDefaults|CFPreferences|(^|[^[:alnum:]_])sysctl[[:space:]]*\(' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-DARWIN-SETTINGS-CAPABILITY" "$file" "$line_number"
    fi

    while IFS= read -r sysctl_line; do
        if [[ "$sysctl_line" != *'sysctlbyname("vm.swapusage", &usage, &size, nil, 0)'* ]]; then
            line_number=$(first_match_line 'sysctlbyname[[:space:]]*\(' "$file" || true)
            report_match "CC-DARWIN-SETTINGS-CAPABILITY" "$file" "${line_number:-1}"
        fi
    done < <(/usr/bin/grep -E 'sysctlbyname[[:space:]]*\(' "$file" || true)

    line_number=$(first_match_line '(^|[^[:alnum:]_])(socket|connect|bind|listen|accept|send|sendto|recv|recvfrom|getaddrinfo)[[:space:]]*\(' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-DARWIN-NETWORK-CAPABILITY" "$file" "$line_number"
    fi

    line_number=$(first_match_line '(^|[^[:alnum:]_])(fork|vfork|execl|execle|execlp|execv|execve|execvp)[[:space:]]*\(' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-DARWIN-PROCESS-CAPABILITY" "$file" "$line_number"
    fi

    line_number=$(first_match_line '(^|[^[:alnum:]_])(setuid|seteuid|setgid|setegid)[[:space:]]*\(|Authorization(Create|Execute)|SMJobBless' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-DARWIN-PRIVILEGE-CAPABILITY" "$file" "$line_number"
    fi
}

scan_content_source_file() {
    local file="$1"
    local owner="$2"
    local line line_number open_record open_line_number open_line normalized_open_line

    scan_common_source_file "$file"

    while IFS= read -r line; do
        case "$line" in
            "import CleanerCore"|"import CryptoKit"|"import Darwin"|"import Foundation")
                ;;
            import*)
                line_number=$(first_match_line "^${line}$" "$file" || true)
                report_match "CC-CONTENT-IMPORT" "$file" "${line_number:-1}"
                ;;
        esac
    done < <(/usr/bin/grep -E '^import[[:space:]]+' "$file" || true)
    line_number=$(first_match_line '^import[[:space:]]+CryptoKit$' "$file" || true)
    if [[ -n "$line_number" && "$file" != "$owner" ]]; then
        report_match "CC-CONTENT-CRYPTOKIT-OWNER" "$file" "$line_number"
    fi

    line_number=$(first_match_line '^import[[:space:]]+Darwin$' "$file" || true)
    if [[ -n "$line_number" && "$file" != "$owner" ]]; then
        report_match "CC-CONTENT-DARWIN-AUTHORITY" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'public[[:space:]]+init[[:space:]]*\([^)]*(root|path|directory)[A-Za-z]*[[:space:]]*:[[:space:]]*URL|mountedVolumeURLs|NSOpenPanel|URL[[:space:]]*\([[:space:]]*fileURLWithPath:[[:space:]]*"/"|/Volumes/' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-CONTENT-ROOT-AUTHORITY" "$file" "$line_number"
    fi

    line_number=$(first_match_line '(print|debugPrint|NSLog|os_log|Logger)[^(]*\([^)]*(locator|URL[.]path|[.]path)' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-CONTENT-LOCATOR-LEAK" "$file" "$line_number"
    fi

    line_number=$(first_match_line '(print|debugPrint|NSLog|os_log|Logger)[^(]*\([^)]*(digest|ContentDigest)|String[[:space:]]*\([[:space:]]*describing:[[:space:]]*digest' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-CONTENT-DIGEST-LEAK" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'O_(WRONLY|RDWR|CREAT|TRUNC|APPEND|EXCL)|Darwin[.](write|pwrite|writev|unlink|unlinkat|rename|renameat|remove|mkdir|mkdirat|rmdir|chmod|fchmod|chown|fchown|lchown|creat|truncate|ftruncate|link|linkat|symlink|symlinkat|mknod|mkfifo|setxattr|fsetxattr|removexattr|fremovexattr|clonefile|copyfile)|(^|[^[:alnum:]_.])(write|pwrite|writev|unlink|unlinkat|rename|renameat|remove|mkdir|mkdirat|rmdir|chmod|fchmod|chown|fchown|lchown|creat|truncate|ftruncate|link|linkat|symlink|symlinkat|mknod|mkfifo|setxattr|fsetxattr|removexattr|fremovexattr|clonefile|copyfile)[[:space:]]*\(' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-CONTENT-DARWIN-AUTHORITY" "$file" "$line_number"
    fi

    while IFS=: read -r open_line_number open_line; do
        [[ -n "$open_line_number" ]] || continue
        normalized_open_line=$(/usr/bin/tr -d '[:space:]' <<< "$open_line")
        if [[ "$normalized_open_line" != 'returnDarwin.open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)' ]]; then
            report_match "CC-CONTENT-DARWIN-AUTHORITY" "$file" "$open_line_number"
        fi
    done < <(/usr/bin/grep -nE '(^|[^[:alnum:]_])((Darwin[.])?open)[[:space:]]*\(' "$file" || true)
}

scan_privacy_file() {
    local file="$1"
    local relative="$2"
    local line_number

    line_number=$(first_match_line 'Analytics|Telemetry|telemetry|Firebase|Sentry|Amplitude|Mixpanel|AdSupport|advertis|SignIn|OAuth|Account|CloudKit|iCloud|Dropbox|GoogleDrive|OneDrive|remote[[:space:]_-]*(inventory|filesystem|classification)' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PRIVACY-CAPABILITY" "$file" "$line_number"
    fi
}

scan_model_inventory_file() {
    local file="$1"
    local line_number

    line_number=$(first_match_line 'CleanableItem|PolicyPort|ExecutionPort|ReceiptPort|ModelStoreCandidate|ModelStoreOperation|OperationPlan' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-MODEL-AUTHORITY" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'removeItem[[:space:]]*\(|trashItem[[:space:]]*\(|replaceItemAt|createFile[[:space:]]*\(|FileHandle[^(]*forWriting|write[[:space:]]*\(' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-MODEL-MUTATION" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'Process[[:space:]]*\(|posix_spawn|system[[:space:]]*\(|NSTask|/bin/(sh|bash|zsh)|/usr/bin/(osascript|open)' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-MODEL-PROCESS" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'URLSession|URLRequest|NSURLSession|NW(Connection|Listener|PathMonitor)|https?://' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-MODEL-NETWORK" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'NSHomeDirectory|homeDirectoryForCurrentUser|ProcessInfo[.]processInfo[.]environment|/Users/' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-MODEL-REAL-HOME" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'environment\[[^]]+\]|[.]ollama/models|FileManager[.]default' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-MODEL-ROOT-INFERENCE" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'resolvingSymlinksInPath|resolvingSymlinksInPath\(|destinationOfSymbolicLink' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-MODEL-LINK-FOLLOW" "$file" "$line_number"
    fi
}

scan_model_inventory_directory() {
    local directory="$1"
    local file
    local discovered_files

    [[ -d "$directory" && -r "$directory" ]] || fail "CC-MODEL-MISSING-SCOPE" "$(location_for "$directory")"

    discovered_files=$(/usr/bin/find "$directory" -type f -name '*.swift' -print) \
        || fail "CC-MODEL-MISSING-SCOPE" "$(location_for "$directory")"
    [[ -n "$discovered_files" ]] || fail "CC-MODEL-MISSING-SCOPE" "$(location_for "$directory")"

    # Source filenames are repository-controlled; newline-delimited discovery keeps find failures observable.
    while IFS= read -r file; do
        scan_model_inventory_file "$file"
    done <<<"$discovered_files"
}

scan_phase5_authority_file() {
    local file="$1"
    local line_number

    line_number=$(first_match_line 'ExecutionPort|ReceiptPort' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PHASE5-EXECUTION-RECEIPT" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'public[[:space:]]+init[[:space:]]*\([^)]*(EligibleCandidate|candidate:)' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PHASE5-PUBLIC-CANDIDATE" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'UserDefaults|isApproved[[:space:]]*:[[:space:]]*Bool|approved[[:space:]]*=[[:space:]]*true' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PHASE5-PERSISTENT-APPROVAL" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'trashItem[[:space:]]*\(|removeItem[[:space:]]*\(|emptyTrash|NSWorkspace' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PHASE5-MUTATION" "$file" "$line_number"
    fi
}

scan_phase5_authority_owners() {
    local directory
    local file
    local owners=(
        "$package_root/Sources/CleanerCore/Policy"
        "$package_root/Sources/CleanerCore/Plans"
        "$package_root/Sources/CleanerCore/Capability"
    )

    for directory in "${owners[@]}"; do
        [[ -d "$directory" && -r "$directory" ]] || fail "CC-PHASE5-MISSING-SCOPE" "$(location_for "$directory")"
        while IFS= read -r -d '' file; do
            scan_phase5_authority_file "$file"
        done < <(/usr/bin/find "$directory" -type f -name '*.swift' -print0)
    done
}

require_cryptokit_plan_digest_adapter() {
    local adapter="$package_root/Sources/CleanerCoreFoundation/CryptoKitPlanDigestAdapter.swift"
    [[ -f "$adapter" && -r "$adapter" ]] || fail "CC-PHASE5-DIGEST-ADAPTER" "CleanerCore/Sources/CleanerCoreFoundation/CryptoKitPlanDigestAdapter.swift"
    /usr/bin/grep -Fq 'import CryptoKit' "$adapter" || fail "CC-PHASE5-DIGEST-ADAPTER" "$(location_for "$adapter")"
    /usr/bin/grep -Fq 'SHA256' "$adapter" || fail "CC-PHASE5-DIGEST-ADAPTER" "$(location_for "$adapter")"
}

scan_phase6_execution_file() {
    local file="$1"
    local line_number

    line_number=$(first_match_line ':[[:space:]]*URL|URL\?|[[:space:]]URL[[:space:]]*\(|\[URL\]' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PHASE6-PUBLIC-INPUT" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'public[[:space:]]+init[[:space:]]*\([^)]*(target:|path:|category:|callback:)' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PHASE6-PUBLIC-OPERATION" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'Codable|Decodable' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PHASE6-DECODED-OPERATION" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'withTaskGroup|TaskGroup|async let' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PHASE6-PARALLEL" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'retry|rollback|restore|compensat' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PHASE6-COMPENSATION" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'ReceiptPort|UserDefaults|historyWriter' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PHASE6-PERSISTENCE" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'emptyTrash|removeItem[[:space:]]*\(|trashItem[[:space:]]*\(' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PHASE6-MUTATION" "$file" "$line_number"
    fi
}

scan_phase6_authority_owners() {
    local execution_root="$package_root/Sources/CleanerCore/Execution"
    local port_file="$package_root/Sources/CleanerCore/Ports/TrashExecutionPort.swift"
    local file

    [[ -d "$execution_root" && -r "$execution_root" ]] || fail "CC-PHASE6-MISSING-SCOPE" "CleanerCore/Sources/CleanerCore/Execution"
    [[ -f "$port_file" && -r "$port_file" ]] || fail "CC-PHASE6-MISSING-SCOPE" "CleanerCore/Sources/CleanerCore/Ports/TrashExecutionPort.swift"

    while IFS= read -r -d '' file; do
        scan_phase6_execution_file "$file"
    done < <(/usr/bin/find "$execution_root" -type f -name '*.swift' -print0)
    scan_phase6_execution_file "$port_file"
}

require_sole_trash_adapter() {
    local adapter="$package_root/Sources/CleanerCoreFoundation/FoundationTrashAdapter.swift"
    local file
    local trash_count

    [[ -f "$adapter" && -r "$adapter" ]] || fail "CC-PHASE6-SOLE-CALL" "CleanerCore/Sources/CleanerCoreFoundation/FoundationTrashAdapter.swift"
    trash_count=$(/usr/bin/grep -c 'trashItem[[:space:]]*(' "$adapter" || true)
    [[ "$trash_count" -eq 1 ]] || fail "CC-PHASE6-SOLE-CALL" "$(location_for "$adapter")"

    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file")" == "FoundationTrashAdapter.swift" ]]; then
            continue
        fi
        if /usr/bin/grep -q 'trashItem[[:space:]]*(' "$file"; then
            fail "CC-PHASE6-SOLE-CALL" "$(location_for "$file")"
        fi
    done < <(/usr/bin/find "$package_root/Sources" -type f -name '*.swift' -print0)
}

scan_receipt_core_file() {
    local file="$1"
    local line_number

    line_number=$(first_match_line '^import[[:space:]]+' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-PURE-IMPORT" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'Codable|Decodable|FileManager|URL[[:space:]]*\(|ApprovalAttestation|trashItem[[:space:]]*\(|UserDefaults|restore|compensat|retry' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "CC-RECEIPT-CORE-AUTHORITY" "$file" "$line_number"
    fi
}

scan_receipt_core_owners() {
    local directory="$package_root/Sources/CleanerCore/Receipts"
    local required
    local file

    [[ -d "$directory" && -r "$directory" ]] || fail "CC-RECEIPT-MISSING-SCOPE" "CleanerCore/Sources/CleanerCore/Receipts"
    for required in ReceiptSchema.swift ReceiptReducer.swift ReceiptReconciliation.swift ReceiptRetention.swift; do
        [[ -f "$directory/$required" && -r "$directory/$required" ]] || fail "CC-RECEIPT-MISSING-SCOPE" "CleanerCore/Sources/CleanerCore/Receipts/$required"
    done

    while IFS= read -r -d '' file; do
        scan_receipt_core_file "$file"
    done < <(/usr/bin/find "$directory" -type f -name '*.swift' -print0)
}

recognize_planned_receipt_adapters() {
    local file
    local planned=(
        "$package_root/Sources/CleanerCoreFoundation/AppSupportReceiptStore.swift"
        "$package_root/Sources/CleanerCoreFoundation/DarwinReceiptLease.swift"
        "$package_root/Sources/CleanerCoreFoundation/FinderReceiptRevealAdapter.swift"
    )

    for file in "${planned[@]}"; do
        [[ -f "$file" ]] || continue
        scan_foundation_source_file "$file"
        if /usr/bin/grep -q 'trashItem[[:space:]]*(' "$file"; then
            fail "CC-PHASE6-SOLE-CALL" "$(location_for "$file")"
        fi
        if [[ "$(basename "$file")" == "FinderReceiptRevealAdapter.swift" ]]; then
            local reveal_count
            reveal_count=$(/usr/bin/grep -c 'activateFileViewerSelecting' "$file" || true)
            if [[ "$reveal_count" -ne 1 ]]; then
                fail "CC-FINDER-REVEAL-OWNER" "$(location_for "$file")"
            fi
            if /usr/bin/grep -Eq 'NSAppleScript|Process[[:space:]]*\(|restore|compensat|retry|emptyTrash|URLSession' "$file"; then
                fail "CC-FINDER-REVEAL-OWNER" "$(location_for "$file")"
            fi
        fi
    done
}

scan_model_inventory_scope() {
    local file
    local boundary_files=(
        "$package_root/Sources/CleanerCore/Bridge/ModelStoreProjection.swift"
        "$package_root/Sources/CleanerCore/Detectors/ModelStoreDetectorRegistration.swift"
        "$package_root/Sources/CleanerCoreFoundation/ModelStoreFilesystemAdapter.swift"
        "$package_root/Sources/CleanerCoreFoundation/ModelStoreFilesystemAdapter+Paths.swift"
        "$package_root/Sources/CleanerCoreFoundation/ModelStoreFilesystemAdapter+Descriptors.swift"
        "$package_root/Sources/CleanerCoreFoundation/ModelStoreFilesystemAdapterSupport.swift"
        "$package_root/Tests/CleanerCoreTests/Support/ModelStoreFixtureFactory.swift"
        "$package_root/Tests/CleanerCoreTests/AIModelHostileFixtureTests.swift"
    )

    scan_model_inventory_directory "$package_root/Sources/CleanerCore/ModelInventory"

    for file in "${boundary_files[@]}"; do
        [[ -f "$file" && -r "$file" ]] || fail "CC-MODEL-MISSING-SCOPE" "$(location_for "$file")"
        scan_model_inventory_file "$file"
    done
}

scan_tree_as_target() {
    local root="$1"
    local target_kind="$2"
    local file
    local found=0

    while IFS= read -r -d '' file; do
        found=1
        case "$target_kind" in
            pure)
                scan_pure_source_file "$file"
                ;;
            foundation)
                scan_foundation_source_file "$file"
                ;;
            darwin)
                scan_darwin_source_file "$file"
                ;;
            content-adapter)
                scan_content_source_file "$file" "$root/StreamingContentEvidenceAdapter.swift"
                ;;
            privacy)
                scan_privacy_file "$file" "$(location_for "$file")"
                ;;
            phase5)
                scan_phase5_authority_file "$file"
                ;;
            phase6)
                scan_phase6_execution_file "$file"
                ;;
            model)
                scan_model_inventory_file "$file"
                ;;
            *)
                fail "CC-UNKNOWN-MODE"
                ;;
        esac
    done < <(/usr/bin/find "$root" -type f -name '*.swift' -print0)

    [[ "$found" -eq 1 ]] || fail "CC-EMPTY-SCOPE" "$(location_for "$root")"
}

validate_exact_target_graph() {
    local manifest="$1"

    /usr/bin/awk '
        BEGIN {
            expected[".target(name:\"CleanerCore\")"] = 1
            expected[".target(name:\"CleanerCoreFoundation\",dependencies:[\"CleanerCore\"])"] = 1
            expected[".target(name:\"CleanerCoreContentAdapter\",dependencies:[\"CleanerCore\"])"] = 1
            expected[".target(name:\"CleanerCoreDarwin\",dependencies:[\"CleanerCore\"])"] = 1
            expected[".testTarget(name:\"CleanerCoreTests\",dependencies:[\"CleanerCore\",\"CleanerCoreFoundation\"])"] = 1
            expected[".testTarget(name:\"CleanerCoreFoundationTests\",dependencies:[\"CleanerCore\",\"CleanerCoreFoundation\"])"] = 1
            expected[".testTarget(name:\"CleanerCoreContentAdapterTests\",dependencies:[\"CleanerCore\",\"CleanerCoreContentAdapter\"])"] = 1
            expected[".testTarget(name:\"CleanerCoreDarwinTests\",dependencies:[\"CleanerCore\",\"CleanerCoreDarwin\"])"] = 1
        }
        {
            if (!capturing && $0 ~ /^[[:space:]]*[.](target|testTarget)[[:space:]]*\(/) {
                capturing = 1
                block = ""
                depth = 0
            }
            if (capturing) {
                block = block $0
                opening = $0
                closing = $0
                depth += gsub(/\(/, "", opening)
                depth -= gsub(/\)/, "", closing)
                if (depth == 0) {
                    gsub(/[[:space:]]/, "", block)
                    sub(/,$/, "", block)
                    observed[block] += 1
                    total += 1
                    capturing = 0
                }
            }
        }
        END {
            if (capturing || total != 8) {
                exit 1
            }
            for (block in expected) {
                if (observed[block] != 1) {
                    exit 1
                }
            }
            for (block in observed) {
                if (!(block in expected)) {
                    exit 1
                }
            }
        }
    ' "$manifest"
}

validate_exact_product_graph() {
    local manifest="$1"

    /usr/bin/awk '
        BEGIN {
            expected[".library(name:\"CleanerCore\",targets:[\"CleanerCore\"])"] = 1
            expected[".library(name:\"CleanerCoreFoundation\",targets:[\"CleanerCoreFoundation\"])"] = 1
            expected[".library(name:\"CleanerCoreContentAdapter\",targets:[\"CleanerCoreContentAdapter\"])"] = 1
            expected[".library(name:\"CleanerCoreDarwin\",targets:[\"CleanerCoreDarwin\"])"] = 1
        }
        {
            if (!capturing && $0 ~ /^[[:space:]]*[.]library[[:space:]]*\(/) {
                capturing = 1
                block = ""
                depth = 0
            }
            if (capturing) {
                block = block $0
                opening = $0
                closing = $0
                depth += gsub(/\(/, "", opening)
                depth -= gsub(/\)/, "", closing)
                if (depth == 0) {
                    gsub(/[[:space:]]/, "", block)
                    sub(/,$/, "", block)
                    observed[block] += 1
                    total += 1
                    capturing = 0
                }
            }
        }
        END {
            if (capturing || total != 4) {
                exit 1
            }
            for (block in expected) {
                if (observed[block] != 1) {
                    exit 1
                }
            }
            for (block in observed) {
                if (!(block in expected)) {
                    exit 1
                }
            }
        }
    ' "$manifest"
}

validate_package_manifest_file() {
    local manifest="$1"
    local compact_manifest

    [[ -f "$manifest" && -r "$manifest" ]] || fail "CC-PACKAGE-MANIFEST" "$(location_for "$manifest")"
    if /usr/bin/grep -Eq '[.]package[[:space:]]*\(|url[[:space:]]*:' "$manifest"; then
        fail "CC-REMOTE-DEPENDENCY" "$(location_for "$manifest")"
    fi
    compact_manifest=$(/usr/bin/tr -d '[:space:]' < "$manifest")
    if [[ "$compact_manifest" == *'.target(name:"CleanerCore",dependencies:'* ]]; then
        fail "CC-PACKAGE-REVERSE-DEPENDENCY" "$(location_for "$manifest")"
    fi
    [[ "$compact_manifest" == *'.library(name:"CleanerCore",targets:["CleanerCore"])'* ]] || fail "CC-PACKAGE-PURE" "$(location_for "$manifest")"
    [[ "$compact_manifest" == *'.target(name:"CleanerCore")'* ]] || fail "CC-PACKAGE-PURE" "$(location_for "$manifest")"
    [[ "$compact_manifest" == *'.library(name:"CleanerCoreFoundation",targets:["CleanerCoreFoundation"])'* ]] || fail "CC-PACKAGE-FOUNDATION" "$(location_for "$manifest")"
    [[ "$compact_manifest" == *'.target(name:"CleanerCoreFoundation",dependencies:["CleanerCore"])'* ]] || fail "CC-PACKAGE-FOUNDATION" "$(location_for "$manifest")"
    [[ "$compact_manifest" == *'.library(name:"CleanerCoreDarwin",targets:["CleanerCoreDarwin"])'* ]] || fail "CC-PACKAGE-DARWIN" "$(location_for "$manifest")"
    [[ "$compact_manifest" == *'.target(name:"CleanerCoreDarwin",dependencies:["CleanerCore"])'* ]] || fail "CC-PACKAGE-DARWIN-DEPENDENCY" "$(location_for "$manifest")"
    [[ "$compact_manifest" == *'.testTarget(name:"CleanerCoreDarwinTests",dependencies:["CleanerCore","CleanerCoreDarwin"])'* ]] || fail "CC-PACKAGE-DARWIN-TEST-DEPENDENCY" "$(location_for "$manifest")"
    [[ "$compact_manifest" == *'.library(name:"CleanerCoreContentAdapter",targets:["CleanerCoreContentAdapter"])'* ]] || fail "CC-PACKAGE-CONTENT-ADAPTER" "$(location_for "$manifest")"
    validate_exact_product_graph "$manifest" || fail "CC-PACKAGE-PRODUCT-GRAPH" "$(location_for "$manifest")"
    validate_exact_target_graph "$manifest" || fail "CC-PACKAGE-TARGET-GRAPH" "$(location_for "$manifest")"
}

validate_package_manifest() {
    validate_package_manifest_file "$package_root/Package.swift"
}

validate_bridge_boundary() {
    # The legacy FileScanner was retired; Home and Disk Cleaner scan only through CleanerCoreLiveScan.
    local file_scanner="$repository_root/MyMacCleaner/Core/Services/FileScanner.swift"

    [[ ! -e "$file_scanner" ]] || fail "CC-BRIDGE-BOUNDARY" "MyMacCleaner/Core/Services/FileScanner.swift"
}

validate_update_owner_boundary() {
    # Sparkle and the custom updater were removed; the app has a typed, non-actionable UpdateCapability only.
    local retired core_file line_number

    for retired in "MyMacCleaner/Core/Services/UpdateManager.swift" "appcast.xml"; do
        [[ ! -e "$repository_root/$retired" ]] || fail "CC-UPDATE-OWNER" "$retired"
    done

    while IFS= read -r -d '' core_file; do
        line_number=$(first_match_line 'UpdateManager|Sparkle|SPU|SUUpdater|URLSession|https?://' "$core_file" || true)
        if [[ -n "$line_number" ]]; then
            report_match "CC-UPDATE-REACHABILITY" "$core_file" "$line_number"
        fi
    done < <(/usr/bin/find "$package_root/Sources" -type f -name '*.swift' -print0)
}

run_product_contract() {
    local pure_root="$package_root/Sources/CleanerCore"
    local foundation_root="$package_root/Sources/CleanerCoreFoundation"
    local darwin_root="$package_root/Sources/CleanerCoreDarwin"
    local content_root="$package_root/Sources/CleanerCoreContentAdapter"
    local content_owner="$content_root/StreamingContentEvidenceAdapter.swift"
    local unselected_owner="$foundation_root/StreamingContentEvidenceAdapter.swift"

    validate_package_manifest
    [[ -d "$pure_root" && -r "$pure_root" ]] || fail "CC-MISSING-SCOPE" "CleanerCore/Sources/CleanerCore"
    [[ -d "$foundation_root" && -r "$foundation_root" ]] || fail "CC-MISSING-SCOPE" "CleanerCore/Sources/CleanerCoreFoundation"
    [[ -d "$darwin_root" && -r "$darwin_root" ]] || fail "CC-MISSING-SCOPE" "CleanerCore/Sources/CleanerCoreDarwin"
    [[ -d "$content_root" && -r "$content_root" ]] || fail "CC-MISSING-SCOPE" "CleanerCore/Sources/CleanerCoreContentAdapter"
    [[ -f "$content_owner" && -r "$content_owner" ]] || fail "CC-CONTENT-CRYPTOKIT-OWNER" "CleanerCore/Sources/CleanerCoreContentAdapter/StreamingContentEvidenceAdapter.swift"
    [[ ! -e "$unselected_owner" ]] || fail "CC-CONTENT-UNSELECTED-BRANCH" "CleanerCore/Sources/CleanerCoreFoundation/StreamingContentEvidenceAdapter.swift"
    /usr/bin/grep -Fq 'import CryptoKit' "$content_owner" || fail "CC-CONTENT-CRYPTOKIT-OWNER" "CleanerCore/Sources/CleanerCoreContentAdapter/StreamingContentEvidenceAdapter.swift"
    /usr/bin/grep -Fq 'import Darwin' "$content_owner" || fail "CC-CONTENT-DARWIN-AUTHORITY" "CleanerCore/Sources/CleanerCoreContentAdapter/StreamingContentEvidenceAdapter.swift"

    scan_tree_as_target "$pure_root" pure
    scan_tree_as_target "$foundation_root" foundation
    scan_tree_as_target "$content_root" content-adapter
    scan_tree_as_target "$darwin_root" darwin
    scan_tree_as_target "$repository_root/MyMacCleaner" privacy
    scan_model_inventory_scope
    validate_bridge_boundary
    validate_update_owner_boundary
    scan_phase5_authority_owners
    require_cryptokit_plan_digest_adapter
    scan_phase6_authority_owners
    require_sole_trash_adapter
    scan_receipt_core_owners
    recognize_planned_receipt_adapters
}

fixture_input=""
fixture_target="pure"
fixture_model_inventory_scope=0
fixture_manifest=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fixture-root)
            [[ $# -ge 2 && -z "$fixture_input" && -z "$fixture_manifest" ]] || fail "CC-INVALID-ROOT"
            fixture_input="$2"
            shift 2
            ;;
        --fixture-target)
            [[ $# -ge 2 ]] || fail "CC-UNKNOWN-MODE"
            case "$2" in
                pure|foundation|content-adapter|darwin|privacy|model|phase5|phase6)
                    fixture_target="$2"
                    ;;
                *)
                    fail "CC-UNKNOWN-MODE"
                    ;;
            esac
            shift 2
            ;;
        --fixture-model-inventory-scope)
            [[ "$fixture_model_inventory_scope" -eq 0 && -z "$fixture_manifest" ]] || fail "CC-UNKNOWN-MODE"
            fixture_model_inventory_scope=1
            shift
            ;;
        --fixture-manifest)
            [[ $# -ge 2 && -z "$fixture_manifest" && -z "$fixture_input" && "$fixture_target" == "pure" && "$fixture_model_inventory_scope" -eq 0 ]] || fail "CC-INVALID-ROOT"
            fixture_manifest="$2"
            shift 2
            ;;
        *)
            fail "CC-UNKNOWN-MODE"
            ;;
    esac
done

if [[ -n "$fixture_manifest" ]]; then
    [[ -z "$fixture_input" && "$fixture_target" == "pure" && "$fixture_model_inventory_scope" -eq 0 ]] || fail "CC-UNKNOWN-MODE"
    is_fixture_authorized || fail "CC-FIXTURE-AUTHORIZATION"
    canonical_manifest=$(validate_fixture_file "$fixture_manifest" "$fixture_root")
    validate_package_manifest_file "$canonical_manifest"
    printf 'CC-PASS: manifest fixture verification passed\n'
    exit 0
fi

if [[ -n "$fixture_input" ]]; then
    is_fixture_authorized || fail "CC-FIXTURE-AUTHORIZATION"
    canonical_fixture=$(validate_root "$fixture_input" "$fixture_root")
    if [[ "$fixture_model_inventory_scope" -eq 1 ]]; then
        [[ "$fixture_target" == "model" ]] || fail "CC-UNKNOWN-MODE"
        scan_model_inventory_directory "$canonical_fixture"
    else
        scan_tree_as_target "$canonical_fixture" "$fixture_target"
    fi
    printf 'CC-PASS: fixture verification passed\n'
    exit 0
fi

[[ "$fixture_target" == "pure" && "$fixture_model_inventory_scope" -eq 0 ]] || fail "CC-UNKNOWN-MODE"
run_product_contract
printf 'CC-PASS: CleanerCore source contract passed\n'
