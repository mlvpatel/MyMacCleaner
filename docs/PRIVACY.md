# Privacy

Local data inventory for MyMacCleaner. Scans, plans, execution, and receipts do
not require a network. Update checking, if present in the app target, is outside
the trust pipeline and is not evidence that a scan can communicate.

## Data inventory

| Data | Purpose | Persistence | Minimization |
|------|---------|-------------|--------------|
| Scan findings | Explain storage | Process memory / projection | Immutable evidence; UI shows opaque identities in Adaptive cards |
| Policy evaluations | Eligibility and rationale | With the scan snapshot | Closed dispositions; no path concatenation in catalogs |
| Review plan | Approval-bound cleanup | Until expiry or invalidation | Digest-bound; not a reusable path list |
| Receipts | Recovery truth | Application Support, bounded | Opaque receipt IDs; estimated vs observed bytes |
| Onboarding flag | First-launch copy | `UserDefaults` key `adaptive.experience.onboarding.acknowledged` | Boolean only |
| Developer presence | Protected-tool cards | Process memory | Presence/protection keys; no chats, credentials, or MCP bodies |
| Memory samples | Coaching | Process memory | Ranked process rows without kill; arguments redacted |

## Retention and deletion

Receipt retention is versioned in `ReceiptRetention`:

- Maximum age: 90 days
- Maximum terminal receipts: 500
- Maximum unresolved receipts: 50

Users can delete local history through the receipt APIs. Deletion is opaque (no
path dump). After Trash is emptied or a volume disappears, recovery is marked
unavailable rather than guessed.

## Logging and redaction

Production diagnostics use closed event codes and counts. Paths, project/model
names, credentials, command text, appcast bodies, and receipt payloads are not
retained in production logs. See SafetyContract redaction tests.

## Update-network boundary

The app has no `URLSession`, no update channel, and no remote packages. Sparkle
and the appcast were removed; Settings shows a non-actionable "updates
unavailable" status. `SC-UPDATE-CAPABILITY` in `scripts/verify-safety-contract.sh`
fails if network or updater code returns.

## Reporting

Privacy and security issues: [SECURITY.md](../SECURITY.md). Do not attach raw
local paths, model names, chats, receipts, or credentials.
