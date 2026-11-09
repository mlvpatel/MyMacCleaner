#!/bin/bash
# Self-test: every rule ID the verifier scripts can print has a `### RULE` entry in
# docs/VERIFIER-RULES.md, so each `see docs/VERIFIER-RULES.md#<rule>` pointer resolves.

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd -P)
rules_doc="$repo_root/docs/VERIFIER-RULES.md"

[[ -r "$rules_doc" ]] || { echo "Missing $rules_doc" >&2; exit 1; }

missing=()
while IFS= read -r rule_id; do
    /usr/bin/grep -Fxq "### $rule_id" "$rules_doc" || missing+=("$rule_id")
done < <(
    /usr/bin/grep -ohE '\b(SC|CC|AE)-[A-Z0-9]+(-[A-Z0-9]+)*' "$repo_root"/scripts/*.sh "$repo_root"/scripts/*.swift \
        | /usr/bin/sort -u
)

if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'Rule ID without an entry in docs/VERIFIER-RULES.md: %s\n' "${missing[@]}" >&2
    exit 1
fi

echo "Verifier rule documentation self-test passed."
