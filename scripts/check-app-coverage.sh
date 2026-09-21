#!/bin/bash
# Fails when MyMacCleaner.app line coverage drops below the committed baseline (a ratchet).
# Usage: scripts/check-app-coverage.sh <TestResults.xcresult | xccov-report.json>

set -euo pipefail

readonly target_name="MyMacCleaner.app"
readonly raise_margin="0.01"

input="${1:?usage: check-app-coverage.sh <path.xcresult|report.json>}"
repository_root=$(cd "$(/usr/bin/dirname "$0")/.." && pwd -P)
baseline_file="$repository_root/scripts/app-coverage-baseline.txt"

[[ -r "$baseline_file" ]] || { echo "APP-COVERAGE-BASELINE-MISSING" >&2; exit 1; }
baseline=$(/usr/bin/grep -Ev '^[[:space:]]*(#|$)' "$baseline_file" | /usr/bin/head -1 | /usr/bin/tr -d '[:space:]')

if [[ "$input" == *.json ]]; then
    report=$(<"$input")
else
    report=$(/usr/bin/xcrun xccov view --report --json "$input")
fi

COVERAGE_REPORT="$report" /usr/bin/python3 - "$target_name" "$baseline" "$raise_margin" <<'PY'
import json, os, sys
target, baseline, margin = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
report = json.loads(os.environ["COVERAGE_REPORT"])
matches = [t for t in report.get("targets", []) if t.get("name") == target]
if not matches:
    print(f"APP-COVERAGE-MISSING: {target} not in coverage report", file=sys.stderr)
    sys.exit(1)
current = float(matches[0]["lineCoverage"])
print(f"APP-COVERAGE: {current:.2%} (baseline {baseline:.2%})")
if current < baseline:
    print("APP-COVERAGE-REGRESSION: coverage fell below scripts/app-coverage-baseline.txt", file=sys.stderr)
    sys.exit(1)
if current >= baseline + margin:
    print(f"::notice::App coverage is {current - baseline:.2%} above baseline; raise scripts/app-coverage-baseline.txt")
PY
