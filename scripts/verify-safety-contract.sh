#!/bin/bash

set -euo pipefail

readonly self_test_sentinel="SAFETY-CONTRACT-SELF-TEST"
readonly script_directory=$(cd "$(dirname "$0")" && pwd -P)
readonly repository_root=$(cd "$script_directory/.." && pwd -P)
readonly script_path="$script_directory/verify-safety-contract.sh"
readonly fixture_root="$repository_root/scripts/tests/fixtures/safety-contract"
readonly default_manifest="$repository_root/scripts/read-only-process-allowlist.txt"
readonly safety_package_root="$repository_root/SafetyContract"
readonly coverage_checker="$script_directory/check-safety-coverage.swift"

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

location_for() {
    local path="$1"

    if [[ "$path" == "$repository_root/"* ]]; then
        printf '%s\n' "${path#"$repository_root/"}"
    else
        printf '%s\n' "${path##*/}"
    fi
}

report_match() {
    local rule_id="$1"
    local file="$2"
    local line_number="$3"

    fail "$rule_id" "$(location_for "$file"):$line_number"
}

first_match_line() {
    local pattern="$1"
    local file="$2"

    /usr/bin/grep -nE -- "$pattern" "$file" | /usr/bin/head -n 1 | /usr/bin/cut -d: -f1
}

first_permanent_mutation_line() {
    local file="$1"
    local presenter="$repository_root/MyMacCleaner/Core/Design/SafetyNoticePresenter.swift"
    local trash_adapter="$repository_root/CleanerCore/Sources/CleanerCoreFoundation/FoundationTrashAdapter.swift"
    local closed_reference_count
    local trash_count

    if [[ "$file" == "$trash_adapter" ]]; then
        trash_count=$(/usr/bin/grep -c 'trashItem[[:space:]]*(' "$file" || true)
        if [[ "$trash_count" -ne 1 ]]; then
            first_match_line 'trashItem[[:space:]]*(' "$file"
            return
        fi
        /usr/bin/grep -nE -- \
            'removeItem[[:space:]]*\(|/bin/rm|rm[[:space:]]+-rf|emptyTrash' \
            "$file" \
            | /usr/bin/head -n 1 \
            | /usr/bin/cut -d: -f1
        return
    fi

    if [[ "$file" == "$presenter" ]]; then
        closed_reference_count=$(
            /usr/bin/grep -Ec '^[[:space:]]*[.]emptyTrash[[:space:]]*$' "$file" || true
        )
        if [[ "$closed_reference_count" -gt 1 ]]; then
            /usr/bin/grep -nE '^[[:space:]]*[.]emptyTrash[[:space:]]*$' "$file" \
                | /usr/bin/tail -n 1 \
                | /usr/bin/cut -d: -f1
            return
        fi

        /usr/bin/grep -nE -- \
            'removeItem[[:space:]]*\(|/bin/rm|rm[[:space:]]+-rf|emptyTrash|trashItem[[:space:]]*\(' \
            "$file" \
            | /usr/bin/grep -vE '^[0-9]+:[[:space:]]*[.]emptyTrash[[:space:]]*$' \
            | /usr/bin/head -n 1 \
            | /usr/bin/cut -d: -f1
        return
    fi

    first_match_line \
        'removeItem[[:space:]]*\(|/bin/rm|rm[[:space:]]+-rf|emptyTrash|trashItem[[:space:]]*\(' \
        "$file"
}

scan_file() {
    local file="$1"
    local line_number

    line_number=$(first_match_line 'NSAppleScript|Authorization(Create|Execute)|with administrator privileges|osascript' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-ELEVATION" "$file" "$line_number"
    fi

    line_number=$(first_permanent_mutation_line "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-PERMANENT-MUTATION" "$file" "$line_number"
    fi

    line_number=$(first_match_line '/usr/sbin/purge|purge[[:space:]]*\(|kill[[:space:]]*\(|terminate[[:space:]]*\(|setItemEnabled[[:space:]]*\(|removeStartupItem[[:space:]]*\(' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-SYSTEM-MUTATION" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'show(Clean|Delete)Confirmation|prepare(Clean|Delete)[[:space:]]*\(|confirm(Clean|Delete)[[:space:]]*\(|cancel(Clean|Delete)[[:space:]]*\(|nodeToDelete|itemsToClean|deleteFiles[[:space:]]*\(|(^|[^[:alnum:]_])on(Clean|Delete|Remove|Trash)[[:alnum:]_]*' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-STALE-MUTATION-CALLBACK" "$file" "$line_number"
    fi

    line_number=$(first_match_line 'role:[[:space:]]*\.destructive|moveToTrash|willDelete|markForDeletion|willBeDeleted' "$file" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-DESTRUCTIVE-UI" "$file" "$line_number"
    fi

    if [[ "${2:-deny}" != "allow" ]]; then
        line_number=$(first_match_line 'Process[[:space:]]*\(' "$file" || true)
        if [[ -n "$line_number" ]]; then
            report_match "SC-UNLISTED-PROCESS" "$file" "$line_number"
        fi
    fi
}

scan_root() {
    local root="$1"
    local file

    if [[ -f "$root" ]]; then
        scan_file "$root"
        return 0
    fi

    while IFS= read -r -d '' file; do
        scan_file "$file"
    done < <(/usr/bin/find "$root" -type f -name '*.swift' -print0)
}

is_fixture_authorized() {
    [[ "${SAFETY_CONTRACT_SELF_TEST_SENTINEL:-}" == "$self_test_sentinel" ]]
}

fixture_forbidden_target_state() {
    local fixture_path="${SAFETY_CONTRACT_TEST_FORBIDDEN_TARGET_FIXTURE:-}"
    local canonical_fixture state

    if [[ -z "$fixture_path" ]]; then
        return 1
    fi

    is_fixture_authorized || fail "SC-FIXTURE-AUTHORIZATION"
    canonical_fixture=$(canonical_path "$fixture_path" || true)
    [[ -n "$canonical_fixture" && -r "$canonical_fixture" ]] || fail "SC-FIXTURE-AUTHORIZATION"

    case "${canonical_fixture##*/}" in
        mymaccleaner-expected-absent.*)
            ;;
        *)
            fail "SC-FIXTURE-AUTHORIZATION"
            ;;
    esac

    case "$canonical_fixture" in
        "$repository_root"|"$repository_root"/*)
            fail "SC-FIXTURE-AUTHORIZATION"
            ;;
    esac

    state=$(<"$canonical_fixture")
    case "$state" in
        absent|reintroduced)
            printf '%s\n' "$state"
            ;;
        *)
            fail "SC-FIXTURE-AUTHORIZATION"
            ;;
    esac
}

forbidden_targets() {
    local mode="$1"

    case "$mode" in
        --system-process-only)
            printf '%s\0' 'MyMacCleaner/Core/Services/AuthorizationService.swift'
            ;;
        --system-ui-applications-only)
            printf '%s\0' 'MyMacCleaner/Features/Applications/Components/UpdateRow.swift'
            ;;
        --diagnostics-network-only)
            printf '%s\0' 'MyMacCleaner/Core/Services/UpdateManager.swift' 'MyMacCleaner/Core/Design/UpdateAvailableButton.swift' 'appcast.xml'
            ;;
        --source-only)
            printf '%s\0' 'MyMacCleaner/Core/Services/AuthorizationService.swift' 'MyMacCleaner/Features/Applications/Components/UpdateRow.swift' 'MyMacCleaner/Core/Services/UpdateManager.swift' 'MyMacCleaner/Core/Design/UpdateAvailableButton.swift' 'appcast.xml'
            ;;
    esac
}

validate_forbidden_targets() {
    local mode="$1"
    local allow_fixture_state="${2:-0}"
    local target fixture_state

    fixture_state=""
    if [[ "$allow_fixture_state" -eq 1 ]]; then
        fixture_state=$(fixture_forbidden_target_state || true)
    fi
    while IFS= read -r -d '' target; do
        if [[ "$fixture_state" == "reintroduced" || ( -z "$fixture_state" && -e "$repository_root/$target" ) ]]; then
            fail "SC-FORBIDDEN-TARGET" "$target"
        fi
    done < <(forbidden_targets "$mode")
}

validate_manifest() {
    local manifest_path="$1"
    local expected_entries=(
        'startup.sfltool.dumpbtm|/usr/bin/sfltool|dumpbtm|MyMacCleaner/Core/Services/StartupItemsService.swift|parseBackgroundItems|Fixed local read-only inventory; no network access.'
        'startup.launchctl.list|/bin/launchctl|list|MyMacCleaner/Core/Services/StartupItemsService.swift|parseLaunchctlItems|Fixed local read-only inventory; no network access.'
        'ports.lsof.tcp-list|/usr/sbin/lsof|-iTCP,-sTCP:LISTEN,ESTABLISHED,-n,-P|MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift|parsePorts|Fixed local read-only inventory; no network access.'
        'health.diskutil.root-info|/usr/sbin/diskutil|info,/|MyMacCleaner/Features/SystemHealth/SystemHealthViewModel.swift|parseDiskInfo|Fixed local read-only inventory; no network access.'
        'activity.lsof.open-files|/usr/sbin/lsof|-Fn,-n,-P,-w,-b|MyMacCleaner/Core/Services/OpenFileActivityObserver.swift|parseOpenFilePaths|Fixed local read-only inventory; no network access.'
    )
    local entries=()
    local line identifier executable arguments owner parser rationale extra prior_entry entry index
    local line_number=0

    [[ -f "$manifest_path" && -r "$manifest_path" ]] || fail "SC-MANIFEST-UNREADABLE"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        [[ -z "$line" || "$line" == \#* ]] && continue

        IFS='|' read -r identifier executable arguments owner parser rationale extra <<< "$line"
        if [[ -n "${extra:-}" || -z "$identifier" || -z "$executable" || -z "$arguments" ]]; then
            fail "SC-MANIFEST-SCHEMA" "$(location_for "$manifest_path"):$line_number"
        fi

        if [[ -z "$owner" || -z "$parser" || -z "$rationale" ]]; then
            fail "SC-MANIFEST-FIELD" "$(location_for "$manifest_path"):$line_number"
        fi

        case "$identifier|$executable|$arguments|$owner|$parser|$rationale" in
            *'*'*|*'?'*|*'['*)
                fail "SC-MANIFEST-WILDCARD" "$(location_for "$manifest_path"):$line_number"
                ;;
        esac

        case "$owner" in
            MyMacCleaner/*.swift)
                ;;
            *)
                fail "SC-MANIFEST-FIELD" "$(location_for "$manifest_path"):$line_number"
                ;;
        esac

        case "$parser" in
            [A-Za-z][A-Za-z0-9_]*)
                ;;
            *)
                fail "SC-MANIFEST-FIELD" "$(location_for "$manifest_path"):$line_number"
                ;;
        esac

        case "$rationale" in
            *'no network'*)
                ;;
            *)
                fail "SC-MANIFEST-FIELD" "$(location_for "$manifest_path"):$line_number"
                ;;
        esac

        entry="$identifier|$executable|$arguments|$owner|$parser|$rationale"
        for prior_entry in "${entries[@]:-}"; do
            if [[ -n "$prior_entry" && "$prior_entry" == "$entry" ]]; then
                fail "SC-MANIFEST-DUPLICATE" "$(location_for "$manifest_path"):$line_number"
            fi
        done
        entries+=("$entry")
    done < "$manifest_path"

    [[ ${#entries[@]} -eq 5 ]] || fail "SC-MANIFEST-COUNT"

    for index in 0 1 2 3 4; do
        [[ "${entries[$index]}" == "${expected_entries[$index]}" ]] || fail "SC-MANIFEST-IDENTITY"
    done
}

mode_targets() {
    local mode="$1"

    case "$mode" in
        --filesystem-only)
            printf '%s\0' 'MyMacCleaner/Core/Services/BrowserCleanerService.swift' 'MyMacCleaner/Core/Services/DuplicateScanner.swift' 'MyMacCleaner/Core/Services/OrphanedFilesScanner.swift' 'MyMacCleaner/Features/SpaceLens/SpaceLensViewModel.swift'
            ;;
        --system-process-only)
            printf '%s\0' 'MyMacCleaner/Core/Services/HomebrewService.swift' 'MyMacCleaner/Core/Services/StartupItemsService.swift' 'MyMacCleaner/Features/Performance/PerformanceViewModel.swift' 'MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift' 'MyMacCleaner/Features/SystemHealth/SystemHealthViewModel.swift' 'MyMacCleaner/Core/Services/OpenFileActivityObserver.swift'
            ;;
        --storage-ui-home-only)
            printf '%s\0' 'MyMacCleaner/Core/Design/SafetyNoticePresenter.swift' 'MyMacCleaner/Features/Home/HomeViewModel.swift' 'MyMacCleaner/Features/Home/HomeView.swift' 'MyMacCleaner/Features/Home/Components/ScanResultsCard.swift'
            ;;
        --storage-ui-disk-browser-only)
            printf '%s\0' 'MyMacCleaner/Core/Design/SafetyNoticePresenter.swift' 'MyMacCleaner/Features/DiskCleaner/DiskCleanerViewModel.swift' 'MyMacCleaner/Features/DiskCleaner/DiskCleanerView.swift' 'MyMacCleaner/Features/DiskCleaner/BrowserPrivacyView.swift' 'MyMacCleaner/Features/DiskCleaner/Components/CleanupCategoryCard.swift'
            ;;
        --storage-ui-space-duplicates-only)
            printf '%s\0' 'MyMacCleaner/Core/Design/SafetyNoticePresenter.swift' 'MyMacCleaner/Features/SpaceLens/SpaceLensViewModel.swift' 'MyMacCleaner/Features/SpaceLens/SpaceLensView.swift' 'MyMacCleaner/Features/SpaceLens/SpaceLensSectionView.swift' 'MyMacCleaner/Features/SpaceLens/Components/SidebarFileRow.swift' 'MyMacCleaner/Features/SpaceLens/Components/BubblePackingView.swift' 'MyMacCleaner/Features/SpaceLens/Components/SingleBubbleView.swift' 'MyMacCleaner/Features/Duplicates/DuplicatesViewModel.swift' 'MyMacCleaner/Features/Duplicates/DuplicatesView.swift'
            ;;
        --storage-ui-orphan-only)
            printf '%s\0' 'MyMacCleaner/Core/Design/SafetyNoticePresenter.swift' 'MyMacCleaner/Features/OrphanedFiles/OrphanedFilesViewModel.swift' 'MyMacCleaner/Features/OrphanedFiles/OrphanedFilesView.swift'
            ;;
        --system-ui-applications-only)
            printf '%s\0' 'MyMacCleaner/Features/Applications/ApplicationsViewModel.swift' 'MyMacCleaner/Features/Applications/ApplicationsView.swift' 'MyMacCleaner/Features/Applications/Components/AppCard.swift' 'MyMacCleaner/Features/Applications/Components/HomebrewCaskRow.swift'
            ;;
        --system-ui-performance-only)
            printf '%s\0' 'MyMacCleaner/Features/Performance/PerformanceViewModel.swift' 'MyMacCleaner/Features/Performance/PerformanceView.swift' 'MyMacCleaner/Features/Performance/Components/ProcessRow.swift'
            ;;
        --system-ui-only)
            printf '%s\0' 'MyMacCleaner/Core/Services/AppState.swift' 'MyMacCleaner/Features/StartupItems/StartupItemsViewModel.swift' 'MyMacCleaner/Features/StartupItems/StartupItemsView.swift' 'MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift' 'MyMacCleaner/Features/PortManagement/PortManagementView.swift'
            ;;
        --diagnostics-network-only)
            printf '%s\0' 'MyMacCleaner/Core/Services/StartupItemsService.swift' 'MyMacCleaner/Core/Models/UpdateCapability.swift'
            ;;
        --source-only)
            printf '%s\0' 'MyMacCleaner/Core/Design/SafetyNoticePresenter.swift' 'MyMacCleaner/Core/Design/UpdateCapabilityView.swift' 'MyMacCleaner/Core/Services/AppState.swift' 'MyMacCleaner/Core/Services/LocalizationManager.swift' 'MyMacCleaner/Core/Services/BrowserCleanerService.swift' 'MyMacCleaner/Core/Services/DuplicateScanner.swift' 'MyMacCleaner/Core/Services/OrphanedFilesScanner.swift' 'MyMacCleaner/Core/Services/HomebrewService.swift' 'MyMacCleaner/Core/Services/StartupItemsService.swift' 'MyMacCleaner/Features/Performance/PerformanceViewModel.swift' 'MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift' 'MyMacCleaner/Features/SystemHealth/SystemHealthViewModel.swift' 'MyMacCleaner/Features/Home/HomeViewModel.swift' 'MyMacCleaner/Features/Home/HomeView.swift' 'MyMacCleaner/Features/Home/Components/ScanResultsCard.swift' 'MyMacCleaner/Features/DiskCleaner/DiskCleanerViewModel.swift' 'MyMacCleaner/Features/DiskCleaner/DiskCleanerView.swift' 'MyMacCleaner/Features/DiskCleaner/BrowserPrivacyView.swift' 'MyMacCleaner/Features/DiskCleaner/Components/CleanupCategoryCard.swift' 'MyMacCleaner/Features/SpaceLens/SpaceLensViewModel.swift' 'MyMacCleaner/Features/SpaceLens/SpaceLensView.swift' 'MyMacCleaner/Features/SpaceLens/SpaceLensSectionView.swift' 'MyMacCleaner/Features/SpaceLens/Components/SidebarFileRow.swift' 'MyMacCleaner/Features/SpaceLens/Components/BubblePackingView.swift' 'MyMacCleaner/Features/SpaceLens/Components/SingleBubbleView.swift' 'MyMacCleaner/Features/Duplicates/DuplicatesViewModel.swift' 'MyMacCleaner/Features/Duplicates/DuplicatesView.swift' 'MyMacCleaner/Features/OrphanedFiles/OrphanedFilesViewModel.swift' 'MyMacCleaner/Features/OrphanedFiles/OrphanedFilesView.swift' 'MyMacCleaner/Features/Applications/ApplicationsViewModel.swift' 'MyMacCleaner/Features/Applications/ApplicationsView.swift' 'MyMacCleaner/Features/Applications/Components/AppCard.swift' 'MyMacCleaner/Features/Applications/Components/HomebrewCaskRow.swift' 'MyMacCleaner/Features/Performance/PerformanceView.swift' 'MyMacCleaner/Features/Performance/Components/ProcessRow.swift' 'MyMacCleaner/Features/StartupItems/StartupItemsViewModel.swift' 'MyMacCleaner/Features/StartupItems/StartupItemsView.swift' 'MyMacCleaner/Features/PortManagement/PortManagementView.swift' 'MyMacCleaner/Core/Models/UpdateCapability.swift' 'MyMacCleaner/Core/Services/OpenFileActivityObserver.swift'
            ;;
        *)
            return 1
            ;;
    esac
}

validate_targets() {
    local mode="$1"
    local target
    local found_target=0

    while IFS= read -r -d '' target; do
        found_target=1
        if [[ "${SAFETY_CONTRACT_TEST_MISSING_TARGET:-}" == "$mode" || ! -f "$repository_root/$target" || ! -r "$repository_root/$target" ]]; then
            fail "SC-MISSING-TARGET" "$target"
        fi
    done < <(mode_targets "$mode")

    [[ $found_target -eq 1 ]] || fail "SC-UNKNOWN-MODE"
}

validate_expected_mode_target() {
    local mode="$1"
    local expected_target="${SAFETY_CONTRACT_TEST_EXPECT_TARGET:-}"
    local target

    [[ -n "$expected_target" ]] || fail "SC-FIXTURE-AUTHORIZATION"
    case "$expected_target" in
        MyMacCleaner/*.swift)
            ;;
        *)
            fail "SC-FIXTURE-AUTHORIZATION"
            ;;
    esac

    while IFS= read -r -d '' target; do
        if [[ "$target" == "$expected_target" ]]; then
            return 0
        fi
    done < <(mode_targets "$mode")

    fail "SC-TARGET-COVERAGE" "$expected_target"
}

scan_mode() {
    local mode="$1"
    local target
    local process_policy="deny"

    validate_targets "$mode"
    if [[ "$mode" == "--system-process-only" || "$mode" == "--system-ui-only" || "$mode" == "--source-only" ]]; then
        process_policy="allow"
    fi
    while IFS= read -r -d '' target; do
        scan_file "$repository_root/$target" "$(process_policy_for_target "$target")"
    done < <(mode_targets "$mode")

    if [[ "$mode" == "--system-ui-applications-only" ]]; then
        validate_applications_copy
    fi

    if [[ "$mode" == "--system-ui-performance-only" || "$mode" == "--source-only" ]]; then
        validate_performance_observations
    fi

    if [[ "$mode" == "--storage-ui-home-only" || "$mode" == "--source-only" ]]; then
        validate_home_memory_guidance
    fi

    if [[ "$mode" == "--system-ui-only" || "$mode" == "--source-only" ]]; then
        validate_system_ui_actions
    fi

    if [[ "$mode" == "--source-only" ]]; then
        validate_read_only_documentation
    fi

    if [[ "$process_policy" == "allow" ]]; then
        validate_fixed_process_adapters
    fi
}

process_policy_for_target() {
    local target="$1"

    case "$target" in
        MyMacCleaner/Core/Services/StartupItemsService.swift|MyMacCleaner/Core/Services/HomebrewService.swift|MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift|MyMacCleaner/Features/SystemHealth/SystemHealthViewModel.swift|MyMacCleaner/Features/Performance/PerformanceViewModel.swift|MyMacCleaner/Core/Services/OpenFileActivityObserver.swift)
            printf '%s\n' 'allow'
            ;;
        *)
            printf '%s\n' 'deny'
            ;;
    esac
}

validate_applications_copy() {
    local catalog="$repository_root/MyMacCleaner/Resources/Applications.xcstrings"
    local line_number

    [[ -f "$catalog" && -r "$catalog" ]] || fail "SC-MISSING-TARGET" "MyMacCleaner/Resources/Applications.xcstrings"

    line_number=$(first_match_line '"applications[.](uninstall|updates)|"applications[.]homebrew[.](cleanup|outdated|updateBadge|upgrade|upgradeAll)|"applications[.]toast[.](allCasksUpgraded|allUpToDate|caskUninstall|caskUpgrade|casksUpgrade|homebrewClean|uninstall|adminDenied|updatesFound)' "$catalog" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-DESTRUCTIVE-COPY" "$catalog" "$line_number"
    fi
}

validate_home_memory_guidance() {
    local catalog="$repository_root/MyMacCleaner/Resources/Home.xcstrings"
    local source="$repository_root/MyMacCleaner/Features/Home/HomeViewModel.swift"
    local view="$repository_root/MyMacCleaner/Features/Home/HomeView.swift"
    local line_number

    [[ -f "$catalog" && -r "$catalog" ]] || fail "SC-MISSING-TARGET" "MyMacCleaner/Resources/Home.xcstrings"

    /usr/bin/grep -Fq 'func openMemoryGuide()' "$source" || fail "SC-HOME-MEMORY-GUIDANCE" "MyMacCleaner/Features/Home/HomeViewModel.swift"
    /usr/bin/grep -Fq 'onNavigateToSection?("performance")' "$source" || fail "SC-HOME-MEMORY-GUIDANCE" "MyMacCleaner/Features/Home/HomeViewModel.swift"
    /usr/bin/grep -Fq 'L("home.actions.memoryGuide")' "$view" || fail "SC-HOME-MEMORY-GUIDANCE" "MyMacCleaner/Features/Home/HomeView.swift"
    /usr/bin/grep -Fq 'action: viewModel.openMemoryGuide' "$view" || fail "SC-HOME-MEMORY-GUIDANCE" "MyMacCleaner/Features/Home/HomeView.swift"

    line_number=$(first_match_line 'freeMemory|free[[:space:]_-]*memory|purge[[:space:]_-]*(disk[[:space:]_-]*)?cache|RAM[[:space:]_-]*(clean|free|optim)' "$source" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-HOME-MEMORY-CLAIM" "$source" "$line_number"
    fi
    line_number=$(first_match_line 'freeMemory|home[.]actions[.]freeMemory|free[[:space:]_-]*memory|purge[[:space:]_-]*(disk[[:space:]_-]*)?cache|RAM[[:space:]_-]*(clean|free|optim)' "$view" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-HOME-MEMORY-CLAIM" "$view" "$line_number"
    fi

    if ! /usr/bin/env node -e '
const fs = require("fs");
const catalog = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const locales = ["en"];
const key = "home.actions.memoryGuide";
if (catalog.strings?.["home.actions.emptyTrash"] || catalog.strings?.["home.actions.freeMemory"] || !catalog.strings?.[key]) process.exit(1);
const entry = catalog.strings[key];
if (JSON.stringify(Object.keys(entry.localizations || {}).sort()) !== JSON.stringify(locales)) process.exit(1);
for (const locale of locales) {
  const value = entry.localizations[locale]?.stringUnit?.value;
  if (typeof value !== "string" || value.length === 0) process.exit(1);
}
' "$catalog"; then
        fail "SC-HOME-MEMORY-LOCALIZATION" "MyMacCleaner/Resources/Home.xcstrings"
    fi
}

validate_performance_observations() {
    local catalog="$repository_root/MyMacCleaner/Resources/Performance.xcstrings"
    local source="$repository_root/MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    local view="$repository_root/MyMacCleaner/Features/Performance/PerformanceView.swift"
    local row="$repository_root/MyMacCleaner/Features/Performance/Components/ProcessRow.swift"
    local line_number

    [[ -f "$catalog" && -r "$catalog" ]] || fail "SC-MISSING-TARGET" "MyMacCleaner/Resources/Performance.xcstrings"

    line_number=$(first_match_line 'MaintenanceTask|onKill|showKillConfirm|confirmationDialog|purge[[:space:]_.-]|runAll|free[[:space:]_-]*RAM|boost[[:space:]_-]*performance|host_statistics64|HOST_VM_INFO64|vm_statistics64|sysctlbyname|vm[.]swapusage|ProcessInfo[.]processInfo[.]physicalMemory|MemoryUsage|SwapUsage|usagePercentage|updateMemoryUsage' "$source" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-PERFORMANCE-MUTATION" "$source" "$line_number"
    fi
    line_number=$(first_match_line 'onKill|showKillConfirm|confirmationDialog|role:[[:space:]]*[.]destructive|performance[.]processes[.]kill|Button[[:space:]]*\{|NavigationLink[[:space:]]*\(|Link[[:space:]]*\(|Menu[[:space:]]*\{|[.]contextMenu|[.]onTapGesture|process[.](user|cpuPercent|arguments|environment|path|content)' "$row" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-PERFORMANCE-PROCESS-ACTION" "$row" "$line_number"
    fi
    line_number=$(first_match_line 'purge[[:space:]_.-]|runAll|free[[:space:]_-]*RAM|boost[[:space:]_-]*performance|memoryGauge|usagePercentage|memoryColor|memoryUsage|performance[.]memory[.](used|free|memoryUsed)' "$view" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-PERFORMANCE-CLAIM" "$view" "$line_number"
    fi

    /usr/bin/grep -Fqx 'import CleanerCore' "$source" || fail "SC-PERFORMANCE-ADAPTER" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fqx 'import CleanerCoreDarwin' "$source" || fail "SC-PERFORMANCE-ADAPTER" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq '@Published private(set) var presentation = MemoryCoachPresentation.unavailable' "$source" || fail "SC-PERFORMANCE-ATOMIC-PRESENTATION" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq 'MemoryObservationPort' "$source" || fail "SC-PERFORMANCE-ADAPTER" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq 'DarwinMemoryObservationAdapter' "$source" || fail "SC-PERFORMANCE-ADAPTER" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq 'WorkloadEvidencePort' "$source" || fail "SC-PERFORMANCE-EVIDENCE" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq 'LocalWorkloadEvidenceProducer(completedInventory: [])' "$source" || fail "SC-PERFORMANCE-EVIDENCE" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq 'MemoryCoachingRules' "$source" || fail "SC-PERFORMANCE-COACHING" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq 'private var refreshTask: Task<Void, Never>?' "$source" || fail "SC-PERFORMANCE-CANCELLATION" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq 'refreshTask?.cancel()' "$source" || fail "SC-PERFORMANCE-CANCELLATION" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq 'refreshGeneration' "$source" || fail "SC-PERFORMANCE-CANCELLATION" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq 'guard isMonitoring else { return }' "$source" || fail "SC-PERFORMANCE-CANCELLATION" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq 'pressureLifecycle?.startPressureSource()' "$source" || fail "SC-PERFORMANCE-PRESSURE-LIFECYCLE" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq 'pressureLifecycle?.stopPressureSource()' "$source" || fail "SC-PERFORMANCE-PRESSURE-LIFECYCLE" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq '.context(sessionID: snapshot.sessionID, process: process)' "$source" || fail "SC-PERFORMANCE-EVIDENCE" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    /usr/bin/grep -Fq 'rules.evaluate(snapshot: snapshot, contexts: contexts)' "$source" || fail "SC-PERFORMANCE-COACHING" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    [[ $(/usr/bin/grep -Fc 'self.presentation = nextPresentation' "$source" || true) -eq 1 ]] || fail "SC-PERFORMANCE-ATOMIC-PRESENTATION" "MyMacCleaner/Features/Performance/PerformanceViewModel.swift"

    /usr/bin/grep -Fq 'viewModel.presentation.pressure' "$view" || fail "SC-PERFORMANCE-PRESSURE" "MyMacCleaner/Features/Performance/PerformanceView.swift"
    /usr/bin/grep -Fq 'viewModel.presentation.fields' "$view" || fail "SC-PERFORMANCE-OBSERVATION" "MyMacCleaner/Features/Performance/PerformanceView.swift"
    /usr/bin/grep -Fq 'viewModel.presentation.processes' "$view" || fail "SC-PERFORMANCE-PROCESS-MODEL" "MyMacCleaner/Features/Performance/PerformanceView.swift"
    /usr/bin/grep -Fq 'viewModel.presentation.explanation' "$view" || fail "SC-PERFORMANCE-COACHING" "MyMacCleaner/Features/Performance/PerformanceView.swift"
    /usr/bin/grep -Fq 'viewModel.presentation.processIssueKeys' "$view" || fail "SC-PERFORMANCE-COACHING" "MyMacCleaner/Features/Performance/PerformanceView.swift"
    /usr/bin/grep -Fq 'case .stale, .unavailableNoFreshEvent:' "$view" || fail "SC-PERFORMANCE-PRESSURE-FRESHNESS" "MyMacCleaner/Features/Performance/PerformanceView.swift"
    /usr/bin/grep -Fq 'case .observed(.warning, _):' "$view" || fail "SC-PERFORMANCE-PRESSURE-FRESHNESS" "MyMacCleaner/Features/Performance/PerformanceView.swift"
    /usr/bin/grep -Fq 'case .observed(.critical, _):' "$view" || fail "SC-PERFORMANCE-PRESSURE-FRESHNESS" "MyMacCleaner/Features/Performance/PerformanceView.swift"
    /usr/bin/grep -Fq 'viewModel.refreshMemoryCoach()' "$view" || fail "SC-PERFORMANCE-REFRESH" "MyMacCleaner/Features/Performance/PerformanceView.swift"
    /usr/bin/grep -Fq 'viewModel.startMonitoring()' "$view" || fail "SC-PERFORMANCE-CANCELLATION" "MyMacCleaner/Features/Performance/PerformanceView.swift"
    /usr/bin/grep -Fq 'viewModel.stopMonitoring()' "$view" || fail "SC-PERFORMANCE-CANCELLATION" "MyMacCleaner/Features/Performance/PerformanceView.swift"

    /usr/bin/grep -Fq 'let process: MemoryCoachProcessRow' "$row" || fail "SC-PERFORMANCE-PROCESS-MODEL" "MyMacCleaner/Features/Performance/Components/ProcessRow.swift"
    /usr/bin/grep -Fq 'process.label.value' "$row" || fail "SC-PERFORMANCE-PROCESS-MODEL" "MyMacCleaner/Features/Performance/Components/ProcessRow.swift"
    /usr/bin/grep -Fq 'process.residentBytes' "$row" || fail "SC-PERFORMANCE-PROCESS-MODEL" "MyMacCleaner/Features/Performance/Components/ProcessRow.swift"
    /usr/bin/grep -Fq 'process.contextKey.rawValue' "$row" || fail "SC-PERFORMANCE-PROCESS-MODEL" "MyMacCleaner/Features/Performance/Components/ProcessRow.swift"

    line_number=$(first_match_line '"performance[.](maintenance|tab[.]maintenance|memory[.](purgeDiskCache|canBeFreed)|processes[.]kill)' "$catalog" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-DESTRUCTIVE-COPY" "$catalog" "$line_number"
    fi

    if ! /usr/bin/env node -e '
const fs = require("fs");
const [catalogPath] = process.argv.slice(1);
const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
const expectedLocales = ["en"];
const requiredKeys = [
  "performance.coach.pressure.normal",
  "performance.coach.pressure.warning",
  "performance.coach.pressure.critical",
  "performance.coach.pressure.unavailable",
  "performance.coach.pressure.stale",
  "performance.coach.cache.managed",
  "performance.coach.cache.unavailable",
  "performance.coach.sample.complete",
  "performance.coach.sample.partial",
  "performance.coach.sample.truncated",
  "performance.coach.sample.cancelled",
  "performance.coach.sample.unavailable",
  "performance.coach.guidance.closeKnownApp",
  "performance.coach.guidance.reduceWorkload",
  "performance.coach.guidance.refresh",
  "performance.coach.context.confirmed",
  "performance.coach.context.inferred",
  "performance.coach.context.absent",
  "performance.coach.process.denied",
  "performance.coach.process.exited",
  "performance.coach.process.shortRead",
  "performance.coach.process.identityChanged",
  "performance.coach.process.unreadable",
  "performance.coach.process.truncated",
  "performance.coach.process.deadlineExceeded",
  "performance.coach.process.cancelled",
  "performance.coach.process.invalidSource",
  "performance.memory.pressure",
  "performance.memory.unavailable",
  "performance.memory.observedAt %@",
  "performance.memory.physicalMemory",
  "performance.memory.active",
  "performance.memory.wired",
  "performance.memory.compressed",
  "performance.memory.cached",
  "performance.memory.purgeable",
  "performance.memory.swap",
  "performance.memory.swapOf %@ %@",
  "performance.refresh",
  "performance.processes.observational",
  "performance.processes.title",
  "performance.processes.empty",
  "performance.processes.pid %@",
  "performance.processes.resident %@"
];
const legacyKeys = [
  "performance.memory.free",
  "performance.memory.used",
  "performance.memory.memoryUsed",
  "performance.memory.managedByMacOS",
  "performance.sample.status",
  "performance.processes.context"
];
if (catalog.sourceLanguage !== "en" || typeof catalog.strings !== "object") process.exit(1);
for (const key of requiredKeys) if (!catalog.strings[key]) process.exit(1);
for (const key of legacyKeys) if (catalog.strings[key]) process.exit(1);
for (const entry of Object.values(catalog.strings)) {
  const locales = Object.keys(entry.localizations || {}).sort();
  if (JSON.stringify(locales) !== JSON.stringify(expectedLocales)) process.exit(1);
  for (const locale of expectedLocales) {
    const value = entry.localizations[locale]?.stringUnit?.value;
    if (typeof value !== "string" || value.length === 0) process.exit(1);
  }
}

const forbiddenClaim = /free\s*ram|free\s*memory|boost\s*performance|optimi[sz]e\s*(ram|memory)|guarantee/i;
for (const entry of Object.values(catalog.strings)) {
  for (const locale of expectedLocales) {
    if (forbiddenClaim.test(entry.localizations[locale].stringUnit.value)) process.exit(1);
  }
}

' "$catalog"; then
        fail "SC-PERFORMANCE-LOCALE-PARITY" "MyMacCleaner/Resources/Performance.xcstrings"
    fi
}

validate_system_ui_actions() {
    local app_state="$repository_root/MyMacCleaner/Core/Services/AppState.swift"
    local startup_catalog="$repository_root/MyMacCleaner/Resources/StartupItems.xcstrings"
    local startup_model="$repository_root/MyMacCleaner/Features/StartupItems/StartupItemsViewModel.swift"
    local startup_view="$repository_root/MyMacCleaner/Features/StartupItems/StartupItemsView.swift"
    local port_model="$repository_root/MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift"
    local port_view="$repository_root/MyMacCleaner/Features/PortManagement/PortManagementView.swift"
    local line_number

    /usr/bin/grep -Fq 'performanceViewModel.stopMonitoring()' "$app_state" || fail "SC-PERFORMANCE-CLEANUP" "MyMacCleaner/Core/Services/AppState.swift"
    if /usr/bin/grep -Fq 'stopProcessMonitoring' "$app_state"; then
        fail "SC-PERFORMANCE-CLEANUP" "MyMacCleaner/Core/Services/AppState.swift"
    fi

    line_number=$(first_match_line 'prepareToggle|confirmToggle|cancelToggle|itemToToggle|showDisableConfirmation|prepareRemove|confirmRemove|cancelRemove|itemToRemove|showRemoveConfirmation' "$startup_model" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-STARTUP-MUTATION" "$startup_model" "$line_number"
    fi
    line_number=$(first_match_line 'onToggle|onRemove|startupItems[.](toggle|remove)' "$startup_view" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-STARTUP-MUTATION" "$startup_view" "$line_number"
    fi
    line_number=$(first_match_line 'prepareKill|confirmKill|cancelKill|connectionToKill|showKillConfirmation' "$port_model" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-PORT-MUTATION" "$port_model" "$line_number"
    fi
    line_number=$(first_match_line 'onKill|prepareKill|confirmKill|cancelKill|connectionToKill|showKillConfirmation|portManagement[.]kill|role:[[:space:]]*[.]destructive' "$port_view" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-PORT-MUTATION" "$port_view" "$line_number"
    fi
    /usr/bin/grep -Fq 'import ServiceManagement' "$startup_model" || fail "SC-STARTUP-SETTINGS-ROUTE" "MyMacCleaner/Features/StartupItems/StartupItemsViewModel.swift"
    /usr/bin/grep -Fq 'SMAppService.openSystemSettingsLoginItems()' "$startup_model" || fail "SC-STARTUP-SETTINGS-ROUTE" "MyMacCleaner/Features/StartupItems/StartupItemsViewModel.swift"
    /usr/bin/grep -Fq 'init(openLoginItemsSettingsAction: @escaping () -> Void = {' "$startup_model" || fail "SC-STARTUP-SETTINGS-ROUTE" "MyMacCleaner/Features/StartupItems/StartupItemsViewModel.swift"
    /usr/bin/grep -Fq 'func openLoginItemsSettings()' "$startup_model" || fail "SC-STARTUP-SETTINGS-ROUTE" "MyMacCleaner/Features/StartupItems/StartupItemsViewModel.swift"
    /usr/bin/grep -Fq 'openLoginItemsSettingsAction()' "$startup_model" || fail "SC-STARTUP-SETTINGS-ROUTE" "MyMacCleaner/Features/StartupItems/StartupItemsViewModel.swift"
    /usr/bin/grep -Fq 'viewModel.openLoginItemsSettings()' "$startup_view" || fail "SC-STARTUP-SETTINGS-ROUTE" "MyMacCleaner/Features/StartupItems/StartupItemsView.swift"
    /usr/bin/grep -Fq 'L("startupItems.openLoginItemsSettings")' "$startup_view" || fail "SC-STARTUP-SETTINGS-ROUTE" "MyMacCleaner/Features/StartupItems/StartupItemsView.swift"
    if /usr/bin/grep -Eq 'Process[[:space:]]*\(|URL\(string:|NSWorkspace|open[[:space:]]+-a|/usr/bin/open' "$startup_model"; then
        fail "SC-STARTUP-SETTINGS-ROUTE" "MyMacCleaner/Features/StartupItems/StartupItemsViewModel.swift"
    fi
    if ! /usr/bin/env node -e '
const fs = require("fs");
const catalog = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const locales = ["en"];
const entry = catalog.strings?.["startupItems.openLoginItemsSettings"];
if (!entry || JSON.stringify(Object.keys(entry.localizations || {}).sort()) !== JSON.stringify(locales)) process.exit(1);
for (const locale of locales) {
  const value = entry.localizations[locale]?.stringUnit?.value;
  if (typeof value !== "string" || value.length === 0) process.exit(1);
}
' "$startup_catalog"; then
        fail "SC-STARTUP-SETTINGS-LOCALIZATION" "MyMacCleaner/Resources/StartupItems.xcstrings"
    fi
}

validate_read_only_documentation() {
    local readme="$repository_root/README.md"
    local home_doc="$repository_root/docs/home.md"
    local performance_doc="$repository_root/docs/performance.md"
    local ports_doc="$repository_root/docs/port-management.md"
    local permissions_doc="$repository_root/docs/permissions.md"
    local startup_doc="$repository_root/docs/startup-items.md"
    local health_doc="$repository_root/docs/system-health.md"
    local applications_doc="$repository_root/docs/applications.md"
    local disk_doc="$repository_root/docs/disk-cleaner.md"
    local duplicates_doc="$repository_root/docs/duplicates.md"
    local orphan_doc="$repository_root/docs/orphaned-files.md"
    local space_doc="$repository_root/docs/space-lens.md"
    local menu_doc="$repository_root/docs/menu-bar.md"
    local docs=(
        "$home_doc"
        "$disk_doc"
        "$space_doc"
        "$orphan_doc"
        "$duplicates_doc"
        "$performance_doc"
        "$applications_doc"
        "$ports_doc"
        "$health_doc"
        "$permissions_doc"
        "$startup_doc"
        "$menu_doc"
    )
    local file
    local line_number

    /usr/bin/grep -Fq '| Performance | Review timestamped memory and process observations |' "$readme" || fail "SC-README-READ-ONLY" 'README.md'
    /usr/bin/grep -Fq '| Port Management | Inspect fixed network connection inventory, filter, and refresh |' "$readme" || fail "SC-README-READ-ONLY" 'README.md'
    /usr/bin/grep -Fq '| System Health | Review startup-item inventory and system stats |' "$readme" || fail "SC-README-READ-ONLY" 'README.md'

    line_number=$(first_match_line 'RAM optimization|maintenance scripts|View and kill processes|Manage startup items' "$readme" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-README-READ-ONLY" "$readme" "$line_number"
    fi

    /usr/bin/grep -Fq 'does not alter local files, memory, processes, or macOS settings.' "$home_doc" || fail "SC-DOCS-READ-ONLY" 'docs/home.md'
    /usr/bin/grep -Fq 'read-only' "$performance_doc" || fail "SC-DOCS-READ-ONLY" 'docs/performance.md'
    /usr/bin/grep -Fq 'Port Management is observational.' "$ports_doc" || fail "SC-DOCS-READ-ONLY" 'docs/port-management.md'
    /usr/bin/grep -Fq 'does not perform administrator-authenticated actions.' "$permissions_doc" || fail "SC-DOCS-READ-ONLY" 'docs/permissions.md'
    /usr/bin/grep -Fq 'does not alter startup entries, launch services, processes, or files.' "$startup_doc" || fail "SC-DOCS-READ-ONLY" 'docs/startup-items.md'
    /usr/bin/grep -Fq 'does not change storage, memory, startup configuration, updates, or hardware settings.' "$health_doc" || fail "SC-DOCS-READ-ONLY" 'docs/system-health.md'
    /usr/bin/grep -Fq 'does not uninstall apps, change Homebrew, download updates, remove leftovers, or alter application files.' "$applications_doc" || fail "SC-DOCS-READ-ONLY" 'docs/applications.md'
    /usr/bin/grep -Fq 'do not delete files, empty Trash, change browser data, run cleanup scripts, or alter system folders.' "$disk_doc" || fail "SC-DOCS-READ-ONLY" 'docs/disk-cleaner.md'
    /usr/bin/grep -Fq 'does not remove files, move items to Trash, choose a keeper, or change filesystem content.' "$duplicates_doc" || fail "SC-DOCS-READ-ONLY" 'docs/duplicates.md'
    /usr/bin/grep -Fq 'does not remove files, move items to Trash, alter app data, or decide that an item is safe to discard.' "$orphan_doc" || fail "SC-DOCS-READ-ONLY" 'docs/orphaned-files.md'
    /usr/bin/grep -Fq 'does not remove files, move items to Trash, alter folders, or perform storage repair.' "$space_doc" || fail "SC-DOCS-READ-ONLY" 'docs/space-lens.md'

    for file in "${docs[@]}"; do
        [[ -f "$file" && -r "$file" ]] || fail "SC-MISSING-TARGET" "$(location_for "$file")"
        line_number=$(first_match_line 'sudo|[[:space:]]purge[[:space:]`]|Run All|Free Memory|Clean Selected|One-Click Empty|Complete Uninstaller|Move to Trash|Add to Cleanup|Click [*][*](Clean|Empty Trash|Kill|Uninstall|Delete)|Force Kill|kill -[0-9]|Safe to Delete|safe to delete|administrator password when|password prompt|admin privileges' "$file" || true)
        if [[ -n "$line_number" ]]; then
            report_match "SC-DOCS-UNSAFE-CLAIM" "$file" "$line_number"
        fi
    done

    line_number=$(first_match_line 'Empty Trash|Free Memory|Release inactive RAM|Purge Disk Cache|one-click cleanup' "$home_doc" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-DOCS-UNSAFE-CLAIM" "$home_doc" "$line_number"
    fi

    line_number=$(first_match_line 'Update All|brew upgrade|download and install|Uninstall Process|Delete selected|Delete] selected|Recovery period|permanently delete' "$applications_doc" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-DOCS-UNSAFE-CLAIM" "$applications_doc" "$line_number"
    fi

    line_number=$(first_match_line 'Deep cleaning|Click [*][*]Clean|Clean] to delete|empty your Trash|delete selected|Safe to Delete|safe to delete|Cleanup Scripts|Optimization Scripts|remove junk' "$disk_doc" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-DOCS-UNSAFE-CLAIM" "$disk_doc" "$line_number"
    fi

    line_number=$(first_match_line 'Remove duplicate|Delete duplicate|Choose a keeper|move selected|Trash Instead' "$duplicates_doc" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-DOCS-UNSAFE-CLAIM" "$duplicates_doc" "$line_number"
    fi

    line_number=$(first_match_line 'Delete leftover|Remove leftover|Safe to discard|Trash Instead|uninstalled apps automatically' "$orphan_doc" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-DOCS-UNSAFE-CLAIM" "$orphan_doc" "$line_number"
    fi

    line_number=$(first_match_line 'Targeted cleanup|delete large|remove large|free up space automatically|storage repair action|repair storage automatically' "$space_doc" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-DOCS-UNSAFE-CLAIM" "$space_doc" "$line_number"
    fi

    line_number=$(first_match_line 'Enable/Disable|Remove Item|Disable unnecessary|remove items|launchctl unload|launchctl bootout' "$startup_doc" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-DOCS-UNSAFE-CLAIM" "$startup_doc" "$line_number"
    fi

    line_number=$(first_match_line 'automatic repair action|repairs issues|fixes issues|optimize|Free Memory|clear cache|disable startup' "$health_doc" || true)
    if [[ -n "$line_number" ]]; then
        report_match "SC-DOCS-UNSAFE-CLAIM" "$health_doc" "$line_number"
    fi
}

validate_fixed_process_adapters() {
    local startup="$repository_root/MyMacCleaner/Core/Services/StartupItemsService.swift"
    local ports="$repository_root/MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift"
    local health="$repository_root/MyMacCleaner/Features/SystemHealth/SystemHealthViewModel.swift"
    local homebrew="$repository_root/MyMacCleaner/Core/Services/HomebrewService.swift"
    local performance="$repository_root/MyMacCleaner/Features/Performance/PerformanceViewModel.swift"
    local activity="$repository_root/MyMacCleaner/Core/Services/OpenFileActivityObserver.swift"
    local file expected count

    for file in "$startup" "$ports" "$health" "$homebrew" "$performance" "$activity"; do
        [[ -f "$file" && -r "$file" ]] || fail "SC-MISSING-TARGET" "$(location_for "$file")"
    done

    expected=2
    count=$(/usr/bin/grep -Ec 'Process[[:space:]]*\(' "$startup" || true)
    [[ "$count" -eq "$expected" ]] || fail "SC-PROCESS-COUNT" "$(location_for "$startup")"
    count=$(/usr/bin/grep -Ec 'Process[[:space:]]*\(' "$ports" || true)
    [[ "$count" -eq 1 ]] || fail "SC-PROCESS-COUNT" "$(location_for "$ports")"
    count=$(/usr/bin/grep -Ec 'Process[[:space:]]*\(' "$health" || true)
    [[ "$count" -eq 1 ]] || fail "SC-PROCESS-COUNT" "$(location_for "$health")"
    count=$(/usr/bin/grep -Ec 'Process[[:space:]]*\(' "$activity" || true)
    [[ "$count" -eq 1 ]] || fail "SC-PROCESS-COUNT" "$(location_for "$activity")"
    count=$((
        $(/usr/bin/grep -Ec 'Process[[:space:]]*\(' "$homebrew" || true) +
        $(/usr/bin/grep -Ec 'Process[[:space:]]*\(' "$performance" || true)
    ))
    [[ "$count" -eq 0 ]] || fail "SC-PROCESS-COUNT" 'unapproved source'

    /usr/bin/grep -Fq 'URL(fileURLWithPath: "/usr/bin/sfltool")' "$startup" || fail "SC-PROCESS-IDENTITY" "$(location_for "$startup")"
    /usr/bin/grep -Fq 'process.arguments = ["dumpbtm"]' "$startup" || fail "SC-PROCESS-IDENTITY" "$(location_for "$startup")"
    /usr/bin/grep -Fq 'URL(fileURLWithPath: "/bin/launchctl")' "$startup" || fail "SC-PROCESS-IDENTITY" "$(location_for "$startup")"
    /usr/bin/grep -Fq 'process.arguments = ["list"]' "$startup" || fail "SC-PROCESS-IDENTITY" "$(location_for "$startup")"
    /usr/bin/grep -Fq 'URL(fileURLWithPath: "/usr/sbin/lsof")' "$ports" || fail "SC-PROCESS-IDENTITY" "$(location_for "$ports")"
    /usr/bin/grep -Fq 'process.arguments = ["-iTCP", "-sTCP:LISTEN,ESTABLISHED", "-n", "-P"]' "$ports" || fail "SC-PROCESS-IDENTITY" "$(location_for "$ports")"
    /usr/bin/grep -Fq 'URL(fileURLWithPath: "/usr/sbin/diskutil")' "$health" || fail "SC-PROCESS-IDENTITY" "$(location_for "$health")"
    /usr/bin/grep -Fq 'process.arguments = ["info", "/"]' "$health" || fail "SC-PROCESS-IDENTITY" "$(location_for "$health")"
    /usr/bin/grep -Eq 'func[[:space:]]+parseDiskInfo' "$health" || fail "SC-PROCESS-IDENTITY" "$(location_for "$health")"
    /usr/bin/grep -Fq 'URL(fileURLWithPath: "/usr/sbin/lsof")' "$activity" || fail "SC-PROCESS-IDENTITY" "$(location_for "$activity")"
    /usr/bin/grep -Fq 'process.arguments = ["-Fn", "-n", "-P", "-w", "-b"]' "$activity" || fail "SC-PROCESS-IDENTITY" "$(location_for "$activity")"
    /usr/bin/grep -Eq 'func[[:space:]]+parseOpenFilePaths' "$activity" || fail "SC-PROCESS-IDENTITY" "$(location_for "$activity")"
}

validate_foundation_contract() {
    local package_manifest="$repository_root/SafetyContract/Package.swift"

    [[ -f "$package_manifest" && -r "$package_manifest" ]] || fail "SC-MISSING-TARGET" 'SafetyContract/Package.swift'
    if /usr/bin/grep -Eq 'Process[[:space:]]*\(|URLSession|NSAppleScript|Authorization' "$package_manifest"; then
        fail "SC-FOUNDATION-CAPABILITY" 'SafetyContract/Package.swift'
    fi
}

validate_diagnostics_and_network() {
    local scoped_sources=(
        'MyMacCleaner/Core/Services/StartupItemsService.swift'
    )
    local disabled_route_sources=(
        'MyMacCleaner/Core/Design/SafetyNoticePresenter.swift'
        'SafetyContract/Sources/SafetyContract/DisabledOperationGateway.swift'
        'SafetyContract/Sources/SafetyContract/DisabledOperationPresentation.swift'
    )
    local source relative_source line_number

    for relative_source in "${scoped_sources[@]}"; do
        source="$repository_root/$relative_source"
        [[ -f "$source" && -r "$source" ]] || fail "SC-MISSING-TARGET" "$relative_source"
        /usr/bin/grep -Fq 'import SafetyContract' "$source" || fail "SC-DIAGNOSTIC-LOGGER" "$relative_source"
        /usr/bin/grep -Fq 'SafetyDiagnosticLogger.emit(' "$source" || fail "SC-DIAGNOSTIC-LOGGER" "$relative_source"
        line_number=$(first_match_line '(^|[^[:alnum:]_])(print|debugPrint|NSLog)[[:space:]]*\(' "$source" || true)
        if [[ -n "$line_number" ]]; then
            report_match "SC-DIAGNOSTIC-RAW-SINK" "$source" "$line_number"
        fi
    done

    while IFS= read -r -d '' source; do
        line_number=$(first_match_line 'URLSession|URLRequest|NSURLSession|Network[.]framework|import[[:space:]]+Network|NW(Connection|Listener|PathMonitor)|https?://' "$source" || true)
        if [[ -n "$line_number" ]]; then
            report_match "SC-NETWORK-CAPABILITY" "$source" "$line_number"
        fi
    done < <(/usr/bin/find "$repository_root/SafetyContract/Sources/SafetyContract" -type f -name '*.swift' -print0)

    # The update stack was removed: no updater, transport, feed, or package may return to the app.
    while IFS= read -r -d '' source; do
        line_number=$(first_match_line 'URLSession|URLRequest|import[[:space:]]+Sparkle|SPU[A-Z]|SUFeedURL|SUPublicEDKey|appcast' "$source" || true)
        if [[ -n "$line_number" ]]; then
            report_match "SC-UPDATE-CAPABILITY" "$source" "$line_number"
        fi
    done < <(/usr/bin/find "$repository_root/MyMacCleaner" -type f \( -name '*.swift' -o -name '*.plist' \) -print0)
    if /usr/bin/grep -Eq 'Sparkle|SPARKLE_' "$repository_root/MyMacCleaner.xcodeproj/project.pbxproj"; then
        fail "SC-UPDATE-CAPABILITY" 'MyMacCleaner.xcodeproj/project.pbxproj'
    fi

    for relative_source in "${disabled_route_sources[@]}"; do
        source="$repository_root/$relative_source"
        [[ -f "$source" && -r "$source" ]] || fail "SC-MISSING-TARGET" "$relative_source"
        line_number=$(first_match_line 'URLSession|URLRequest|NSURLSession|Network[.]framework|import[[:space:]]+Network|NW(Connection|Listener|PathMonitor)|https?://' "$source" || true)
        if [[ -n "$line_number" ]]; then
            report_match "SC-NETWORK-CAPABILITY" "$source" "$line_number"
        fi
    done
}

validateNoRawDiagnosticSinks() {
    local source line_number

    while IFS= read -r -d '' source; do
        line_number=$(first_match_line '(^|[^[:alnum:]_])(print|debugPrint|NSLog)[[:space:]]*\(' "$source" || true)
        if [[ -n "$line_number" ]]; then
            report_match "SC-DIAGNOSTIC-RAW-SINK" "$source" "$line_number"
        fi
    done < <(/usr/bin/find "$repository_root/MyMacCleaner" -type f -name '*.swift' -print0)
}

run_complete_source_contract() {
    local composed_modes=(
        --filesystem-only
        --system-process-only
        --storage-ui-home-only
        --storage-ui-disk-browser-only
        --storage-ui-space-duplicates-only
        --storage-ui-orphan-only
        --system-ui-applications-only
        --system-ui-performance-only
        --system-ui-only
    )
    local mode

    validate_foundation_contract
    # Scan the complete manifest first. Narrower passes retain family-specific
    # invariants but cannot hide a full-mode target from the generic denylist.
    scan_mode --source-only
    for mode in "${composed_modes[@]}"; do
        scan_mode "$mode"
    done
    validate_diagnostics_and_network
    validateNoRawDiagnosticSinks
    validate_read_only_documentation
}

run_canonical_gate() (
    local coverage_directory coverage_profile coverage_json freshness_marker llvm_profdata llvm_cov test_binary
    local profile_paths=()
    local test_binaries=()
    local candidate

    [[ -f "$coverage_checker" && -r "$coverage_checker" ]] || fail "SC-COVERAGE-CHECKER"
    [[ -d "$safety_package_root/Sources/SafetyContract" ]] || fail "SC-COVERAGE-SOURCE-ROOT"

    coverage_directory=$(mktemp -d "${TMPDIR:-/tmp}/mymaccleaner-safety-coverage.XXXXXX") || fail "SC-COVERAGE-TEMPORARY"
    trap 'rm -rf "$coverage_directory"' EXIT

    bash "$repository_root/scripts/tests/verify-safety-contract-foundation-tests.sh"
    "$script_path" --source-only
    freshness_marker="$coverage_directory/profiles-before-test"
    touch "$freshness_marker"
    bash "$repository_root/scripts/run-safety-tests.sh" --enable-code-coverage --parallel

    # Classic SwiftPM writes profiles under .build/<triple>/debug/codecov; Xcode 27's build
    # system writes them under .build/**/out/Products/Debug/codecov. Match on the codecov
    # segment, still newer than the freshness marker, so this build's profiles are found on
    # either layout (and stale profiles from an earlier build are excluded by -newer).
    while IFS= read -r -d '' candidate; do
        profile_paths+=("$candidate")
    done < <(/usr/bin/find "$safety_package_root/.build" -type f -path '*/codecov/*.profraw' -newer "$freshness_marker" -print0)
    [[ ${#profile_paths[@]} -gt 0 ]] || fail "SC-COVERAGE-PROFILE"

    # Anchor the test binaries to the product directory that holds this build's fresh profiles
    # (the parent of their codecov directory). That yields the single merged
    # SafetyContractPackageTests.xctest (classic) or the per-target *Tests.xctest bundles
    # (Xcode 27) from THIS build, while ignoring stale bundles an earlier toolchain left in
    # .build. Exclude .dSYM DWARF copies, which also live under the bundle's MacOS directory.
    coverage_product_root=$(/usr/bin/dirname "$(/usr/bin/dirname "${profile_paths[0]}")")
    while IFS= read -r -d '' candidate; do
        test_binaries+=("$candidate")
    done < <(/usr/bin/find "$coverage_product_root" -type f -path '*Tests.xctest/Contents/MacOS/*Tests' -not -path '*.dSYM/*' -print0)
    [[ ${#test_binaries[@]} -ge 1 ]] || fail "SC-COVERAGE-TEST-BINARY"
    for test_binary in "${test_binaries[@]}"; do
        [[ -x "$test_binary" ]] || fail "SC-COVERAGE-TEST-BINARY"
    done

    llvm_profdata=$(/usr/bin/xcrun --find llvm-profdata 2>/dev/null) || fail "SC-COVERAGE-TOOL"
    llvm_cov=$(/usr/bin/xcrun --find llvm-cov 2>/dev/null) || fail "SC-COVERAGE-TOOL"
    [[ -x "$llvm_profdata" && -x "$llvm_cov" ]] || fail "SC-COVERAGE-TOOL"

    coverage_profile="$coverage_directory/coverage.profdata"
    coverage_json="$coverage_directory/coverage.json"
    "$llvm_profdata" merge -sparse "${profile_paths[@]}" -o "$coverage_profile" > "$coverage_directory/llvm-profdata.log" 2>&1 \
        || fail "SC-COVERAGE-PROFILE"
    # Pass every discovered test binary to llvm-cov (first positional, rest via -object) so
    # coverage merges across the per-target bundles (Xcode 27) or the single merged bundle
    # (classic). Built as a bash 3.2-safe index loop that never expands an empty array.
    export_objects=("${test_binaries[0]}")
    export_index=1
    while (( export_index < ${#test_binaries[@]} )); do
        export_objects+=(-object "${test_binaries[$export_index]}")
        export_index=$(( export_index + 1 ))
    done
    "$llvm_cov" export -instr-profile "$coverage_profile" "${export_objects[@]}" > "$coverage_json" 2> "$coverage_directory/llvm-cov.log" \
        || fail "SC-COVERAGE-EXPORT"
    [[ -s "$coverage_json" ]] || fail "SC-COVERAGE-EXPORT"

    if [[ -n "${CODEX_SANDBOX:-}" ]]; then
        mkdir -p "$coverage_directory/module-cache"
        CLANG_MODULE_CACHE_PATH="$coverage_directory/module-cache/clang" \
            SWIFTPM_MODULECACHE_OVERRIDE="$coverage_directory/module-cache/swiftpm" \
            /usr/bin/swift "$coverage_checker" \
                --input "$coverage_json" \
                --source-root "$safety_package_root/Sources/SafetyContract" \
                --minimum 80
    else
        /usr/bin/swift "$coverage_checker" \
            --input "$coverage_json" \
            --source-root "$safety_package_root/Sources/SafetyContract" \
            --minimum 80
    fi
)

fixture_input=""
fixture_manifest=""
product_mode=""
fixture_forbidden_target_contract=0
fixture_mode_target_contract=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fixture-root)
            [[ $# -ge 2 && -z "$fixture_input" ]] || fail "SC-INVALID-INPUT"
            fixture_input="$2"
            shift 2
            ;;
        --fixture-manifest)
            [[ $# -ge 2 && -z "$fixture_manifest" ]] || fail "SC-INVALID-INPUT"
            fixture_manifest="$2"
            shift 2
            ;;
        --product-root)
            [[ $# -ge 2 ]] || fail "SC-INVALID-INPUT"
            if [[ -n "$fixture_input" ]]; then
                fail "SC-MIXED-ROOTS"
            fi
            fail "SC-INVALID-INPUT"
            ;;
        --fixture-forbidden-target-contract)
            fixture_forbidden_target_contract=1
            shift
            ;;
        --fixture-mode-target-contract)
            fixture_mode_target_contract=1
            shift
            ;;
        --foundation-only|--filesystem-only|--system-process-only|--storage-ui-home-only|--storage-ui-disk-browser-only|--storage-ui-space-duplicates-only|--storage-ui-orphan-only|--system-ui-applications-only|--system-ui-performance-only|--system-ui-only|--diagnostics-network-only|--source-only)
            [[ -z "$product_mode" ]] || fail "SC-INVALID-INPUT"
            product_mode="$1"
            shift
            ;;
        *)
            fail "SC-UNKNOWN-MODE"
            ;;
    esac
done

if [[ $fixture_forbidden_target_contract -eq 1 && $fixture_mode_target_contract -eq 1 ]]; then
    fail "SC-MIXED-ROOTS"
fi

if [[ -n "$fixture_input" ]]; then
    [[ -z "$fixture_manifest" && -z "$product_mode" && $fixture_forbidden_target_contract -eq 0 && $fixture_mode_target_contract -eq 0 ]] || fail "SC-MIXED-ROOTS"
    is_fixture_authorized || fail "SC-FIXTURE-AUTHORIZATION"

    canonical_fixture=$(canonical_path "$fixture_input" || true)
    if [[ -z "$canonical_fixture" || ! -r "$canonical_fixture" ]]; then
        fail "SC-INVALID-INPUT"
    fi

    case "$canonical_fixture" in
        "$fixture_root"|"$fixture_root"/*)
            ;;
        *)
            fail "SC-FIXTURE-AUTHORIZATION"
            ;;
    esac

    scan_root "$canonical_fixture"
    printf 'SC-PASS: fixture verification passed\n'
    exit 0
fi

if [[ -z "$product_mode" && -z "$fixture_manifest" && $fixture_forbidden_target_contract -eq 0 && $fixture_mode_target_contract -eq 0 ]]; then
    run_canonical_gate
    printf 'SC-PASS: canonical safety contract verification passed\n'
    exit 0
fi

[[ -n "$product_mode" ]] || fail "SC-UNKNOWN-MODE"

if [[ -n "${SAFETY_CONTRACT_TEST_FORBIDDEN_TARGET_FIXTURE:-}" && $fixture_forbidden_target_contract -eq 0 ]]; then
    fail "SC-FIXTURE-AUTHORIZATION"
fi

if [[ -n "${SAFETY_CONTRACT_TEST_EXPECT_TARGET:-}" && $fixture_mode_target_contract -eq 0 ]]; then
    fail "SC-FIXTURE-AUTHORIZATION"
fi

if [[ -n "$fixture_manifest" ]]; then
    [[ "$product_mode" == "--foundation-only" ]] || fail "SC-INVALID-INPUT"
    is_fixture_authorized || fail "SC-FIXTURE-AUTHORIZATION"
    manifest_path=$(canonical_path "$fixture_manifest" || true)
    [[ -n "$manifest_path" ]] || fail "SC-MANIFEST-UNREADABLE"
else
    manifest_path="$default_manifest"
fi

validate_manifest "$manifest_path"

if [[ $fixture_forbidden_target_contract -eq 1 ]]; then
    is_fixture_authorized || fail "SC-FIXTURE-AUTHORIZATION"
    [[ "$product_mode" == "--system-process-only" || "$product_mode" == "--system-ui-applications-only" || "$product_mode" == "--source-only" ]] || fail "SC-INVALID-INPUT"
    [[ -n "${SAFETY_CONTRACT_TEST_FORBIDDEN_TARGET_FIXTURE:-}" ]] || fail "SC-FIXTURE-AUTHORIZATION"
    validate_forbidden_targets "$product_mode" 1
    printf 'SC-PASS: expected-absent target contract passed\n'
    exit 0
fi

if [[ $fixture_mode_target_contract -eq 1 ]]; then
    is_fixture_authorized || fail "SC-FIXTURE-AUTHORIZATION"
    [[ "$product_mode" != "--foundation-only" ]] || fail "SC-INVALID-INPUT"
    [[ -z "$fixture_manifest" && $fixture_forbidden_target_contract -eq 0 ]] || fail "SC-MIXED-ROOTS"
    validate_targets "$product_mode"
    validate_expected_mode_target "$product_mode"
    printf 'SC-PASS: mode target contract passed\n'
    exit 0
fi

validate_forbidden_targets "$product_mode"

if [[ "$product_mode" == "--foundation-only" ]]; then
    validate_foundation_contract
    printf 'SC-PASS: foundation verification passed\n'
    exit 0
fi

if [[ "$product_mode" == "--source-only" ]]; then
    # Retain the complete manifest check before composing individual scopes so a
    # missing source cannot be hidden by an otherwise passing subset.
    validate_targets "$product_mode"
    run_complete_source_contract
    printf 'SC-PASS: %s verification passed\n' "$product_mode"
    exit 0
fi

if [[ "$product_mode" == "--diagnostics-network-only" ]]; then
    validate_targets "$product_mode"
    validate_diagnostics_and_network
    printf 'SC-PASS: %s verification passed\n' "$product_mode"
    exit 0
fi

scan_mode "$product_mode"
printf 'SC-PASS: %s verification passed\n' "$product_mode"
