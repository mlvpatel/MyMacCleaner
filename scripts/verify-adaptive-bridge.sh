#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
target="${1:-$repo_root/MyMacCleaner/Features/AdaptiveExperience/AdaptiveExperienceViewModel.swift}"

# Prints `RULE: location: detail` and the rule's entry in docs/VERIFIER-RULES.md, then exits.
fail() {
    local rule_id="$1"
    local location="${2:-}"
    local detail="${3:-}"

    printf '%s' "$rule_id" >&2
    [[ -z "$location" ]] || printf ': %s' "$location" >&2
    [[ -z "$detail" ]] || printf ': %s' "$detail" >&2
    printf '\n  see docs/VERIFIER-RULES.md#%s\n' "$(printf '%s' "$rule_id" | /usr/bin/tr '[:upper:]' '[:lower:]')" >&2
    exit 1
}

location_for() {
    local path="$1"

    if [[ "$path" == "$repo_root/"* ]]; then
        printf '%s\n' "${path#"$repo_root/"}"
    else
        printf '%s\n' "${path##*/}"
    fi
}

# Fails with the rule at the first line of the file that matches the pattern, naming the match.
fail_on_match() {
    local rule_id="$1"
    local pattern="$2"
    local file="$3"
    local hit

    hit=$(/usr/bin/grep -nEo -- "$pattern" "$file" | /usr/bin/head -n 1 || true)
    [[ -z "$hit" ]] || fail "$rule_id" "$(location_for "$file"):${hit%%:*}" "${hit#*:}"
}

target_location=$(location_for "$target")

[[ -f "$target" && -r "$target" ]] || fail "AE-BRIDGE-MISSING" "$target_location"

fail_on_match "AE-BRIDGE-AUTHORITY" 'FileScanner|trashItem|removeItem|Process[[:space:]]*\(|URLSession|posix_spawn|NSAppleScript|isApproved|ApprovalAttestation|MoveToTrash|ScanRequest|GeneralMacRootKind|FileManager|URL\(' "$target"

/usr/bin/grep -Fq 'import CleanerCore' "$target" \
    || fail "AE-BRIDGE-IMPORT" "$target_location" "missing 'import CleanerCore'"

/usr/bin/grep -Fq 'AdaptiveSafeIntent' "$target" \
    || fail "AE-BRIDGE-INTENT" "$target_location" "missing 'AdaptiveSafeIntent'"

fail_on_match "AE-BRIDGE-PERSONA" 'persona|isTechnicalUser|cleanScore|cleanliness' "$target"

printf 'AE-BRIDGE: PASS\n'
