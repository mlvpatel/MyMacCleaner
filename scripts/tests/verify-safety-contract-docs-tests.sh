#!/bin/bash
# Self-test: a repository doc that shows a forbidden deletion or elevation API in a fenced code
# example fails SC-DOCS-UNSAFE-CLAIM at that line, while an inline-code mention above it does not.

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd -P)
verifier="$repo_root/scripts/verify-safety-contract.sh"
probe_name="verifier-docs-self-test-$$.md"
probe="$repo_root/docs/$probe_name"
trap '/bin/rm -f "$probe"' EXIT

cat > "$probe" <<'EOF'
# Probe

The contract forbids `removeItem(at:)`; mentioning it in prose is fine.

```swift
try FileManager.default.removeItem(at: url)
```
EOF

if output=$("$verifier" --source-only 2>&1); then
    echo "Expected SC-DOCS-UNSAFE-CLAIM for a fenced removeItem example" >&2
    exit 1
fi
if ! /usr/bin/grep -Fq "SC-DOCS-UNSAFE-CLAIM: docs/$probe_name:6" <<<"$output"; then
    echo "Expected SC-DOCS-UNSAFE-CLAIM at docs/$probe_name:6, got: $output" >&2
    exit 1
fi

echo "Safety documentation self-test passed."
