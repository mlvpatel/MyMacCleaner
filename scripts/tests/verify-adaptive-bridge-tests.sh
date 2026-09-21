#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd -P)
verifier="$repo_root/scripts/verify-adaptive-bridge.sh"
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/mymaccleaner-adaptive-bridge.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

expect_success() {
    local label="$1"
    local path="$2"
    if ! "$verifier" "$path" >/dev/null; then
        echo "Expected success: $label" >&2
        exit 1
    fi
}

expect_failure() {
    local label="$1"
    local expected="$2"
    local path="$3"
    local output
    if output=$("$verifier" "$path" 2>&1); then
        echo "Expected failure: $label" >&2
        exit 1
    fi
    if ! /usr/bin/grep -Fq "$expected" <<<"$output"; then
        echo "Expected $expected for $label" >&2
        exit 1
    fi
}

cat > "$temporary_root/safe.swift" <<'EOF'
import CleanerCore
enum AdaptiveSafeIntent { case refresh }
EOF

cat > "$temporary_root/url.swift" <<'EOF'
import CleanerCore
enum AdaptiveSafeIntent { case refresh }
let path = URL(fileURLWithPath: "/tmp")
EOF

cat > "$temporary_root/persona.swift" <<'EOF'
import CleanerCore
enum AdaptiveSafeIntent { case refresh }
let isTechnicalUser = true
EOF

expect_success "closed intents" "$temporary_root/safe.swift"
expect_failure "url authority" "AE-BRIDGE-AUTHORITY" "$temporary_root/url.swift"
expect_failure "persona flag" "AE-BRIDGE-PERSONA" "$temporary_root/persona.swift"
expect_success "production view model" "$repo_root/MyMacCleaner/Features/AdaptiveExperience/AdaptiveExperienceViewModel.swift"

echo "AE-BRIDGE-SELF-TEST: PASS"
