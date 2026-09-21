#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd -P)
verifier="$repo_root/scripts/verify-safety-contract.sh"
fixtures="$repo_root/scripts/tests/fixtures/safety-contract"
sentinel="SAFETY-CONTRACT-SELF-TEST"
manifest="$repo_root/scripts/read-only-process-allowlist.txt"
temporary_directory=""
forbidden_target_fixture=""

cleanup() {
    if [[ -n "$temporary_directory" ]]; then
        /bin/rm -f "$temporary_directory"/*
        /bin/rmdir "$temporary_directory"
    fi
    if [[ -n "$forbidden_target_fixture" ]]; then
        /bin/rm -f "$forbidden_target_fixture"
    fi
}

trap cleanup EXIT

expect_success() {
    local label="$1"
    shift

    if "$@"; then
        return 0
    fi

    echo "Expected success: $label" >&2
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
        exit 1
    fi
}

expect_manifest_failure() {
    local label="$1"
    local expected_rule="$2"
    local candidate_manifest="$3"

    expect_failure "$label" "$expected_rule" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
        "$verifier" --foundation-only --fixture-manifest "$candidate_manifest"
}

expect_mode_target() {
    local label="$1"
    local mode="$2"
    local target="$3"

    expect_success "$label" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
        SAFETY_CONTRACT_TEST_EXPECT_TARGET="$target" \
        "$verifier" --fixture-mode-target-contract "$mode"
}

write_forbidden_target_fixture() {
    local state="$1"

    forbidden_target_fixture=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/mymaccleaner-expected-absent.XXXXXX")
    printf '%s\n' "$state" > "$forbidden_target_fixture"
}

if [[ "${1:-}" == "--fixtures-only" ]]; then
    :
elif [[ $# -ne 0 ]]; then
    echo "Unknown self-test option: $1" >&2
    exit 64
fi

expect_success "safe fixture" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/safe"
expect_failure "elevation fixture" "SC-ELEVATION" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/unsafe/Elevation.swift"
expect_failure "permanent mutation fixture" "SC-PERMANENT-MUTATION" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/unsafe/PermanentMutation.swift"
expect_failure "Empty Trash invocation fixture" "SC-PERMANENT-MUTATION" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/unsafe/EmptyTrashInvocation.swift"
expect_failure "Empty Trash function reference fixture" "SC-PERMANENT-MUTATION" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/unsafe/EmptyTrashReference.swift"
expect_failure "Empty Trash multiline reference fixture" "SC-PERMANENT-MUTATION" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/unsafe/EmptyTrashMultilineReference.swift"
expect_failure "missing fixture root" "SC-INVALID-INPUT" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/missing"
expect_failure "unreadable fixture root" "SC-INVALID-INPUT" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root /dev/null
expect_failure "unknown mode" "SC-UNKNOWN-MODE" "$verifier" --unknown-mode
expect_failure "mixed roots" "SC-MIXED-ROOTS" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/safe" --product-root "$repo_root/MyMacCleaner"
expect_failure "missing sentinel" "SC-FIXTURE-AUTHORIZATION" \
    "$verifier" --fixture-root "$fixtures/safe"

if [[ "${1:-}" == "--fixtures-only" ]]; then
    echo "Safety contract fixture verifier self-tests passed."
    exit 0
fi

expect_failure "system mutation fixture" "SC-SYSTEM-MUTATION" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/unsafe/SystemMutation.swift"
expect_failure "stale storage ui fixture" "SC-STALE-MUTATION-CALLBACK" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/unsafe/StaleStorageUI.swift"
for callback in OnClean OnDelete OnRemove OnTrash; do
    expect_failure "$callback mutation callback fixture" "SC-STALE-MUTATION-CALLBACK" \
        env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
        "$verifier" --fixture-root "$fixtures/unsafe/${callback}Callback.swift"
done
expect_failure "unlisted process fixture" "SC-UNLISTED-PROCESS" env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/unsafe/UnlistedProcess.swift"
expect_success "foundation verifier" "$verifier" --foundation-only
expect_success "fixed system process verifier" "$verifier" --system-process-only

scheduled_modes=(
    --filesystem-only
    --system-process-only
    --storage-ui-home-only
    --storage-ui-disk-browser-only
    --storage-ui-space-duplicates-only
    --storage-ui-orphan-only
    --system-ui-applications-only
    --system-ui-performance-only
    --system-ui-only
    --diagnostics-network-only
    --source-only
)

write_forbidden_target_fixture "absent"
expect_failure "forbidden target fixture rejected by normal product mode" "SC-FIXTURE-AUTHORIZATION" \
    env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    SAFETY_CONTRACT_TEST_FORBIDDEN_TARGET_FIXTURE="$forbidden_target_fixture" \
    "$verifier" --system-process-only

for scheduled_mode in "${scheduled_modes[@]}"; do
    expect_failure "missing target for $scheduled_mode" "SC-MISSING-TARGET" \
        env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
        SAFETY_CONTRACT_TEST_MISSING_TARGET="$scheduled_mode" \
        "$verifier" "$scheduled_mode"
done

expect_mode_target "Home mode scans presenter" --storage-ui-home-only \
    MyMacCleaner/Core/Design/SafetyNoticePresenter.swift
expect_mode_target "Home mode scans results component" --storage-ui-home-only \
    MyMacCleaner/Features/Home/Components/ScanResultsCard.swift
expect_mode_target "Disk mode scans presenter" --storage-ui-disk-browser-only \
    MyMacCleaner/Core/Design/SafetyNoticePresenter.swift
expect_mode_target "Disk mode scans category component" --storage-ui-disk-browser-only \
    MyMacCleaner/Features/DiskCleaner/Components/CleanupCategoryCard.swift
expect_mode_target "Space and duplicates mode scans presenter" --storage-ui-space-duplicates-only \
    MyMacCleaner/Core/Design/SafetyNoticePresenter.swift
expect_mode_target "Orphan mode scans presenter" --storage-ui-orphan-only \
    MyMacCleaner/Core/Design/SafetyNoticePresenter.swift
expect_mode_target "System UI mode scans shared app state" --system-ui-only \
    MyMacCleaner/Core/Services/AppState.swift
expect_mode_target "Full source mode scans presenter" --source-only \
    MyMacCleaner/Core/Design/SafetyNoticePresenter.swift
expect_mode_target "Full source mode scans Home component" --source-only \
    MyMacCleaner/Features/Home/Components/ScanResultsCard.swift
expect_mode_target "Full source mode scans Disk component" --source-only \
    MyMacCleaner/Features/DiskCleaner/Components/CleanupCategoryCard.swift
expect_mode_target "Full source mode scans Applications card component" --source-only \
    MyMacCleaner/Features/Applications/Components/AppCard.swift
expect_mode_target "Full source mode scans Homebrew cask component" --source-only \
    MyMacCleaner/Features/Applications/Components/HomebrewCaskRow.swift
expect_failure "mode target contract rejects unlisted target" "SC-TARGET-COVERAGE" \
    env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    SAFETY_CONTRACT_TEST_EXPECT_TARGET=MyMacCleaner/Features/DiskCleaner/Components/CleanupCategoryCard.swift \
    "$verifier" --fixture-mode-target-contract --storage-ui-home-only
expect_failure "mode target contract requires sentinel" "SC-FIXTURE-AUTHORIZATION" \
    env SAFETY_CONTRACT_TEST_EXPECT_TARGET=MyMacCleaner/Core/Design/SafetyNoticePresenter.swift \
    "$verifier" --fixture-mode-target-contract --storage-ui-home-only
expect_failure "mode target override rejected by product mode" "SC-FIXTURE-AUTHORIZATION" \
    env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    SAFETY_CONTRACT_TEST_EXPECT_TARGET=MyMacCleaner/Core/Design/SafetyNoticePresenter.swift \
    "$verifier" --storage-ui-home-only
expect_failure "conflicting fixture contracts" "SC-MIXED-ROOTS" \
    env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    SAFETY_CONTRACT_TEST_FORBIDDEN_TARGET_FIXTURE="$forbidden_target_fixture" \
    SAFETY_CONTRACT_TEST_EXPECT_TARGET=MyMacCleaner/Core/Services/StartupItemsService.swift \
    "$verifier" --fixture-forbidden-target-contract --fixture-mode-target-contract \
    --system-process-only

expect_success "Home storage UI verifier" "$verifier" --storage-ui-home-only
expect_success "Disk and browser storage UI verifier" "$verifier" --storage-ui-disk-browser-only
expect_success "Space and duplicates storage UI verifier" "$verifier" --storage-ui-space-duplicates-only
expect_success "Orphan storage UI verifier" "$verifier" --storage-ui-orphan-only

expect_success "deleted authorization target" \
    env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    SAFETY_CONTRACT_TEST_FORBIDDEN_TARGET_FIXTURE="$forbidden_target_fixture" \
    "$verifier" --fixture-forbidden-target-contract --system-process-only

expect_success "deleted Applications update target" \
    env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    SAFETY_CONTRACT_TEST_FORBIDDEN_TARGET_FIXTURE="$forbidden_target_fixture" \
    "$verifier" --fixture-forbidden-target-contract --system-ui-applications-only

/bin/rm -f "$forbidden_target_fixture"
forbidden_target_fixture=""
write_forbidden_target_fixture "reintroduced"
expect_failure "reintroduced authorization target" "SC-FORBIDDEN-TARGET" \
    env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    SAFETY_CONTRACT_TEST_FORBIDDEN_TARGET_FIXTURE="$forbidden_target_fixture" \
    "$verifier" --fixture-forbidden-target-contract --system-process-only

expect_failure "reintroduced Applications update target" "SC-FORBIDDEN-TARGET" \
    env SAFETY_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    SAFETY_CONTRACT_TEST_FORBIDDEN_TARGET_FIXTURE="$forbidden_target_fixture" \
    "$verifier" --fixture-forbidden-target-contract --system-ui-applications-only

temporary_directory=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mymaccleaner-manifest.XXXXXX")

printf 'malformed\n' > "$temporary_directory/malformed.txt"
expect_manifest_failure "malformed manifest" "SC-MANIFEST-SCHEMA" "$temporary_directory/malformed.txt"

/bin/cp "$manifest" "$temporary_directory/duplicate.txt"
/usr/bin/sed -n '2p' "$manifest" >> "$temporary_directory/duplicate.txt"
expect_manifest_failure "duplicate manifest entry" "SC-MANIFEST-DUPLICATE" "$temporary_directory/duplicate.txt"

printf '%s\n' \
    'startup.sfltool.dumpbtm|/usr/bin/*|dumpbtm|MyMacCleaner/Core/Services/StartupItemsService.swift|parseBackgroundItems|Read-only local inventory.' \
    'startup.launchctl.list|/bin/launchctl|list|MyMacCleaner/Core/Services/StartupItemsService.swift|parseLaunchctlItems|Read-only local inventory.' \
    'ports.lsof.tcp-list|/usr/sbin/lsof|-iTCP,-sTCP:LISTEN,ESTABLISHED,-n,-P|MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift|parsePorts|Read-only local inventory.' \
    'health.diskutil.root-info|/usr/sbin/diskutil|info,/|MyMacCleaner/Features/SystemHealth/SystemHealthViewModel.swift|parseDiskInfo|Read-only local inventory.' \
    > "$temporary_directory/wildcard.txt"
expect_manifest_failure "wildcard manifest entry" "SC-MANIFEST-WILDCARD" "$temporary_directory/wildcard.txt"

printf '%s\n' \
    'startup.sfltool.dumpbtm|/usr/bin/sfltool|dumpbtm||parseBackgroundItems|Read-only local inventory.' \
    'startup.launchctl.list|/bin/launchctl|list|MyMacCleaner/Core/Services/StartupItemsService.swift|parseLaunchctlItems|Read-only local inventory.' \
    'ports.lsof.tcp-list|/usr/sbin/lsof|-iTCP,-sTCP:LISTEN,ESTABLISHED,-n,-P|MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift|parsePorts|Read-only local inventory.' \
    'health.diskutil.root-info|/usr/sbin/diskutil|info,/|MyMacCleaner/Features/SystemHealth/SystemHealthViewModel.swift|parseDiskInfo|Read-only local inventory.' \
    > "$temporary_directory/missing-owner.txt"
expect_manifest_failure "missing manifest owner" "SC-MANIFEST-FIELD" "$temporary_directory/missing-owner.txt"

printf '%s\n' \
    'startup.sfltool.dumpbtm|/usr/bin/sfltool|dumpbtm|MyMacCleaner/Core/Services/StartupItemsService.swift||Fixed local read-only inventory; no network access.' \
    'startup.launchctl.list|/bin/launchctl|list|MyMacCleaner/Core/Services/StartupItemsService.swift|parseLaunchctlItems|Fixed local read-only inventory; no network access.' \
    'ports.lsof.tcp-list|/usr/sbin/lsof|-iTCP,-sTCP:LISTEN,ESTABLISHED,-n,-P|MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift|parsePorts|Fixed local read-only inventory; no network access.' \
    'health.diskutil.root-info|/usr/sbin/diskutil|info,/|MyMacCleaner/Features/SystemHealth/SystemHealthViewModel.swift|parseDiskInfo|Fixed local read-only inventory; no network access.' \
    > "$temporary_directory/missing-parser.txt"
expect_manifest_failure "missing manifest parser" "SC-MANIFEST-FIELD" "$temporary_directory/missing-parser.txt"

printf '%s\n' \
    'startup.sfltool.dumpbtm|/usr/bin/sfltool|dumpbtm|MyMacCleaner/Core/Services/StartupItemsService.swift|parseBackgroundItems|' \
    'startup.launchctl.list|/bin/launchctl|list|MyMacCleaner/Core/Services/StartupItemsService.swift|parseLaunchctlItems|Read-only local inventory.' \
    'ports.lsof.tcp-list|/usr/sbin/lsof|-iTCP,-sTCP:LISTEN,ESTABLISHED,-n,-P|MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift|parsePorts|Read-only local inventory.' \
    'health.diskutil.root-info|/usr/sbin/diskutil|info,/|MyMacCleaner/Features/SystemHealth/SystemHealthViewModel.swift|parseDiskInfo|Read-only local inventory.' \
    > "$temporary_directory/missing-rationale.txt"
expect_manifest_failure "missing manifest rationale" "SC-MANIFEST-FIELD" "$temporary_directory/missing-rationale.txt"

printf '%s\n' \
    'startup.sfltool.dumpbtm|/usr/bin/sfltool|dumpbtm,extra|MyMacCleaner/Core/Services/StartupItemsService.swift|parseBackgroundItems|Fixed local read-only inventory; no network access.' \
    'startup.launchctl.list|/bin/launchctl|list|MyMacCleaner/Core/Services/StartupItemsService.swift|parseLaunchctlItems|Fixed local read-only inventory; no network access.' \
    'ports.lsof.tcp-list|/usr/sbin/lsof|-iTCP,-sTCP:LISTEN,ESTABLISHED,-n,-P|MyMacCleaner/Features/PortManagement/PortManagementViewModel.swift|parsePorts|Fixed local read-only inventory; no network access.' \
    'health.diskutil.root-info|/usr/sbin/diskutil|info,/|MyMacCleaner/Features/SystemHealth/SystemHealthViewModel.swift|parseDiskInfo|Fixed local read-only inventory; no network access.' \
    > "$temporary_directory/identity-mismatch.txt"
expect_manifest_failure "fixed identity mismatch" "SC-MANIFEST-IDENTITY" "$temporary_directory/identity-mismatch.txt"

echo "Safety contract fixture verifier self-tests passed."
