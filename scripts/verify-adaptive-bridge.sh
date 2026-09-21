#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
target="${1:-$repo_root/MyMacCleaner/Features/AdaptiveExperience/AdaptiveExperienceViewModel.swift}"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

[[ -f "$target" && -r "$target" ]] || fail "AE-BRIDGE-MISSING"

if /usr/bin/grep -Eq 'FileScanner|trashItem|removeItem|Process[[:space:]]*\(|URLSession|posix_spawn|NSAppleScript|isApproved|ApprovalAttestation|MoveToTrash|ScanRequest|GeneralMacRootKind|FileManager|URL\(' "$target"; then
    fail "AE-BRIDGE-AUTHORITY"
fi

if ! /usr/bin/grep -Fq 'import CleanerCore' "$target"; then
    fail "AE-BRIDGE-IMPORT"
fi

if ! /usr/bin/grep -Fq 'AdaptiveSafeIntent' "$target"; then
    fail "AE-BRIDGE-INTENT"
fi

if /usr/bin/grep -Eq 'persona|isTechnicalUser|cleanScore|cleanliness' "$target"; then
    fail "AE-BRIDGE-PERSONA"
fi

printf 'AE-BRIDGE: PASS\n'
