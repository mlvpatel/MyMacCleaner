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

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

[[ -f "$catalog" ]] || fail "AE-CATALOG-MISSING"
/usr/bin/python3 - "$catalog" <<'PY' || fail "AE-CATALOG-LINT"
import json, sys
catalog = json.load(open(sys.argv[1], encoding="utf-8"))
expected = ["en"]
if catalog.get("sourceLanguage") != "en":
    raise SystemExit(1)
strings = catalog.get("strings") or {}
for key, entry in strings.items():
    if not (key.startswith("adaptive.") or key.startswith("receipt.recovery.") or key.startswith("navigation.adaptive")):
        continue
    locales = sorted((entry.get("localizations") or {}).keys())
    if locales != expected:
        raise SystemExit(f"AE-LOCALE-PARITY:{key}")
    for locale in expected:
        value = entry["localizations"][locale].get("stringUnit", {}).get("value")
        if not isinstance(value, str) or not value.strip():
            raise SystemExit(f"AE-EMPTY:{key}:{locale}")
        if "/Users/" in value or "rm -rf" in value.lower():
            raise SystemExit(f"AE-SENSITIVE:{key}")
PY

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
    adaptive.refresh.hint \
    adaptive.mode.hint \
    adaptive.receipts.close.hint \
    adaptive.approval.button \
    adaptive.approval.confirm
do
    /usr/bin/grep -Fq "\"$key\"" "$catalog" || fail "AE-CATALOG-KEY:$key"
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
    'developer.inventory'
    'adaptive.modelInventory'
)

for view in "${views[@]}"; do
    [[ -f "$view" ]] || fail "AE-VIEW-MISSING"
    /usr/bin/grep -Fq 'accessibilityIdentifier("adaptive.' "$view" \
        || /usr/bin/grep -Fq 'identifier: "adaptive.' "$view" \
        || /usr/bin/grep -Fq 'accessibilityIdentifier("developer.' "$view" \
        || fail "AE-STABLE-ID"
    if /usr/bin/grep -Eq 'FileScanner|trashItem|cleanScore|isTechnicalUser' "$view"; then
        fail "AE-VIEW-AUTHORITY"
    fi
done
combined=$(cat "${views[@]}")
for id in "${required_ids[@]}"; do
    /usr/bin/grep -Fq "$id" <<<"$combined" || fail "AE-ID-MISSING:$id"
done

printf 'AE-EXPERIENCE: PASS\n'
