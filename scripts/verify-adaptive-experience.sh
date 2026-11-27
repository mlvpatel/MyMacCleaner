#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
catalog="$repo_root/MyMacCleaner/Resources/Common.xcstrings"
views=(
    "$repo_root/MyMacCleaner/Features/AdaptiveExperience/AdaptiveExperienceView.swift"
    "$repo_root/MyMacCleaner/Features/AdaptiveExperience/ExperienceDashboardView.swift"
    "$repo_root/MyMacCleaner/Features/AdaptiveExperience/ReviewEvidenceView.swift"
    "$repo_root/MyMacCleaner/Features/AdaptiveExperience/ReceiptRecoveryView.swift"
    "$repo_root/MyMacCleaner/Features/AdaptiveExperience/Components/TrustStateCard.swift"
)

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

# Catalog location of a string key, with its line number when the key is present.
catalog_location_for_key() {
    local line_number

    line_number=$(/usr/bin/grep -nF -- "\"$1\"" "$catalog" | /usr/bin/head -n 1 | /usr/bin/cut -d: -f1 || true)
    printf '%s%s\n' "$catalog_location" "${line_number:+:$line_number}"
}

catalog_location=$(location_for "$catalog")

[[ -f "$catalog" ]] || fail "AE-CATALOG-MISSING" "$catalog_location"
# The linter prints `RULE<TAB>detail` for the first problem it finds, or nothing when the catalog is clean.
lint_finding=$(/usr/bin/python3 - "$catalog" <<'PY'
import json, sys
catalog = json.load(open(sys.argv[1], encoding="utf-8"))
expected = ["en"]

def report(rule, detail):
    print(f"{rule}\t{detail}")
    sys.exit(0)

if catalog.get("sourceLanguage") != "en":
    report("AE-CATALOG-LINT", "sourceLanguage is not en")
strings = catalog.get("strings") or {}
for key, entry in strings.items():
    if not (key.startswith("adaptive.") or key.startswith("receipt.recovery.") or key.startswith("navigation.adaptive")):
        continue
    locales = sorted((entry.get("localizations") or {}).keys())
    if locales != expected:
        report("AE-LOCALE-PARITY", key)
    for locale in expected:
        value = entry["localizations"][locale].get("stringUnit", {}).get("value")
        if not isinstance(value, str) or not value.strip():
            report("AE-EMPTY", f"{key} ({locale})")
        if "/Users/" in value or "rm -rf" in value.lower():
            report("AE-SENSITIVE", key)
PY
) || fail "AE-CATALOG-LINT" "$catalog_location" "not readable as JSON"
if [[ -n "$lint_finding" ]]; then
    lint_rule="${lint_finding%%$'\t'*}"
    lint_detail="${lint_finding#*$'\t'}"
    if [[ "$lint_rule" == "AE-CATALOG-LINT" ]]; then
        fail "$lint_rule" "$catalog_location" "$lint_detail"
    fi
    fail "$lint_rule" "$(catalog_location_for_key "${lint_detail%% (*}")" "$lint_detail"
fi

for key in \
    navigation.adaptiveExperience \
    adaptive.onboarding.title \
    adaptive.onboarding.learn-evidence \
    adaptive.scan.stop \
    adaptive.scan.stop.hint \
    adaptive.warning.permission \
    adaptive.warning.external-volume \
    adaptive.warning.changed-evidence \
    adaptive.warning.unknown-layout \
    adaptive.section.opportunities \
    adaptive.section.protected \
    adaptive.section.memory \
    adaptive.section.coverage \
    adaptive.section.history \
    adaptive.mode.guided \
    adaptive.explain.guided.recovery \
    adaptive.explain.standard.policy \
    adaptive.explain.standard.recovery \
    adaptive.explain.technical.policy \
    adaptive.explain.technical.plan \
    adaptive.explain.technical.receipt \
    receipt.recovery.mayBeAvailable \
    adaptive.developer.cursor.present \
    adaptive.modelInventory.title \
    adaptive.modelInventory.addRoot \
    adaptive.refresh.hint \
    adaptive.mode.hint \
    adaptive.receipts.close.hint \
    adaptive.permission.close \
    adaptive.execution.progress \
    adaptive.execution.summary \
    adaptive.execution.viewReceipt \
    adaptive.approval.button \
    adaptive.approval.confirm
do
    /usr/bin/grep -Fq "\"$key\"" "$catalog" || fail "AE-CATALOG-KEY" "$catalog_location" "missing key $key"
done

required_ids=(
    'adaptive.onboarding.sheet'
    'adaptive.onboarding.continue'
    'adaptive.onboarding.learn-evidence'
    'adaptive.mode.picker'
    'adaptive.mode.guided'
    'adaptive.dashboard'
    'adaptive.section.opportunities'
    'adaptive.section.protected-data'
    'adaptive.scan.progress'
    'adaptive.scan.stop'
    'adaptive.evidence.refresh'
    'adaptive.review'
    'adaptive.approval.button'
    'adaptive.approval.invalid'
    'adaptive.approval.confirm'
    'adaptive.permission.close'
    'developer.inventory'
    'adaptive.modelInventory'
    'adaptive.modelInventory.addRoot'
)

for view in "${views[@]}"; do
    [[ -f "$view" ]] || fail "AE-VIEW-MISSING" "$(location_for "$view")"
    /usr/bin/grep -Fq 'accessibilityIdentifier("adaptive.' "$view" \
        || /usr/bin/grep -Fq 'identifier: "adaptive.' "$view" \
        || /usr/bin/grep -Fq 'accessibilityIdentifier("developer.' "$view" \
        || fail "AE-STABLE-ID" "$(location_for "$view")" "no adaptive. or developer. accessibility identifier"
    fail_on_match "AE-VIEW-AUTHORITY" 'FileScanner|trashItem|cleanScore|isTechnicalUser' "$view"
done
combined=$(cat "${views[@]}")
for id in "${required_ids[@]}"; do
    /usr/bin/grep -Fq "$id" <<<"$combined" \
        || fail "AE-ID-MISSING" "MyMacCleaner/Features/AdaptiveExperience" "no view uses identifier $id"
done

printf 'AE-EXPERIENCE: PASS\n'
