#!/bin/bash
# Fails when a signed release/archive app carries an entitlement that lets other code run inside it.
# The app is not sandboxed and asks for Full Disk Access, so injected code would inherit that access.
#
# Usage: scripts/check-signed-entitlements.sh <path/to/MyMacCleaner.app>
# Used by scripts/release.sh (verify_app_signature) and the Archive Test job in pr-checks.yml.

set -euo pipefail

readonly FORBIDDEN_ENTITLEMENTS=(
    com.apple.security.cs.disable-library-validation
    com.apple.security.cs.allow-dyld-environment-variables
    com.apple.security.cs.allow-unsigned-executable-memory
    com.apple.security.get-task-allow
)

[[ $# -eq 1 && -d "$1" ]] || { printf 'ENTITLEMENTS-ERROR: usage: %s <app>\n' "$0" >&2; exit 64; }

# codesign prints the entitlements as a canonical XML plist; strip whitespace so each entry reads
# <key>NAME</key><true/> and an exact key match cannot hit a longer key that shares a prefix.
entitlements="$(/usr/bin/codesign -d --entitlements - --xml "$1" 2>/dev/null)" \
    || { printf 'ENTITLEMENTS-ERROR: could not read entitlements of %s\n' "$1" >&2; exit 1; }
entitlements="$(/usr/bin/tr -d '[:space:]' <<<"$entitlements")"

found=0
for key in "${FORBIDDEN_ENTITLEMENTS[@]}"; do
    if [[ "$entitlements" == *"<key>$key</key><true/>"* ]]; then
        printf 'ENTITLEMENTS-ERROR: %s is signed with forbidden entitlement %s\n' "$1" "$key" >&2
        found=1
    fi
done
[[ $found -eq 0 ]] || exit 1
printf 'Entitlements OK: none of %s\n' "${FORBIDDEN_ENTITLEMENTS[*]}"
