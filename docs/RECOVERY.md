# Recovery

Trash-first recovery semantics. MyMacCleaner does not empty Trash, permanently
delete, or auto-restore files.

## Before mutation

The app writes an atomic local journal of intent, then records planned, started,
moved, skipped-stale, failed, or cancelled outcomes after each item.

The only v1 mutation is `MoveToTrash` created from an approved, unexpired
`ReviewPlan`. Immediately before each item, `FreshEvidenceRevalidator` compares
current identity, topology, volume, type, metadata, semantic owner, and approved
root to the frozen evidence. Any change yields a per-item skipped-stale no-op.
A fresh scan must also still find the item policy-eligible (including the
open-file check) and inside the named cache scope, and the final probe requires
a link count of 1; otherwise the item is skipped, never moved.

Items run one at a time. A partial run is never represented as complete success.

## After a move

A successful move records the Foundation-returned Trash URL. Finder reveal uses
that URL through `FinderReceiptRevealAdapter`. The UI must not invent a `.Trash`
path. If macOS reports the move but returns no URL, the item is still recorded
as moved and reveal reports its location as unknown.

## When recovery is impossible

If Trash was emptied, the item was removed, or the volume disappeared, receipts
must say recovery is unavailable. Do not promise restore.

## History

- Bounded retention: 90 days and 500 terminal receipts (`ReceiptRetention`)
- Unresolved/quarantined records are not pruned as ordinary terminals
- Users may delete local history; deletion does not print paths
- On relaunch, interrupted journals reconcile to terminal or needs-attention
  states without repeating a mutation

## Adaptive Experience

The receipts sheet shows opaque receipt IDs and recovery markers
(`receipt.recovery.mayBeAvailable`, `receipt.recovery.unavailable`). Its
approve/confirm step is the only path to Trash execute: it passes the reviewed
digest to `AdaptiveTrustSession.executeDisplayedPlan`.

## Related tests

- `CleanerCore/Tests/CleanerCoreTests/ReceiptTrustCoreTests.swift`
- `CleanerCore/Tests/CleanerCoreFoundationTests/ReceiptRecoveryTests.swift`
- `CleanerCore/Tests/CleanerCoreFoundationTests/ReceiptRetentionAndDeletionTests.swift`
