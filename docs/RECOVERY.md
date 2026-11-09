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

Quit does not cut a run short. While items move, `applicationShouldTerminate`
asks the user: **Keep Moving** cancels the quit; **Stop and Quit** uses the same
stop as the Stop button (no item starts after it, the current one finishes and
is recorded), and the app replies to the quit only after the run has ended and
its receipt is written. A crash or forced quit can still interrupt a run; the
next launch reconciles it as described below.

## After a move

A successful move records the Foundation-returned Trash URL. The UI must not
invent a `.Trash` path. If macOS reports the move but returns no URL, the item
is still recorded as moved and its location is unknown.

If the journal write fails after an item moved, the run reports
`receiptIncomplete`: the session keeps each moved item's returned Trash location
in memory until the app quits and lists them in the receipts sheet, so the user
can still find what moved. The failure notice has **Open Receipts**, which opens
that sheet. On the next launch that receipt reconciles to
needs-attention; the move is never repeated.

## When recovery is impossible

If Trash was emptied, the item was removed, or the volume disappeared, receipts
must say recovery is unavailable. Do not promise restore.

## History

- Bounded retention: 90 days and 500 terminal receipts (`ReceiptRetention`)
- Unresolved/quarantined records are not pruned as ordinary terminals
- Users may delete local history; deletion does not print paths
- On relaunch, interrupted journals reconcile to terminal or needs-attention
  states without repeating a mutation
- A crash mid-write leaves only a hidden temp file: the loader ignores it (and
  `.DS_Store`), and the next history access sweeps it under the lease. A folder
  holding only temp files never got its intent, so nothing ran and it is removed
- A run is refused, with nothing moved, when another app instance holds the
  history lock (`historyBusy`), when 50 unresolved receipts are already kept
  (`reviewRequired`), or when history cannot be opened or written
  (`receiptHistoryUnavailable`). When history cannot be listed, the receipts
  sheet says so and why instead of showing an empty list
- Each of these logs a closed `RECEIPT_*` event code with counts only, at
  notice or error level so the unified log keeps it

## Adaptive Experience

The receipts sheet shows opaque receipt IDs, each receipt's item count, and
recovery markers (`receipt.recovery.mayBeAvailable`, `receipt.recovery.unavailable`). Its
approve/confirm step is the only path to Trash execute: it passes the reviewed
digest to `AdaptiveTrustSession.executeDisplayedPlan`.

## Related tests

- `CleanerCore/Tests/CleanerCoreTests/ReceiptTrustCoreTests.swift`
- `CleanerCore/Tests/CleanerCoreFoundationTests/ReceiptRecoveryTests.swift`
- `CleanerCore/Tests/CleanerCoreFoundationTests/ReceiptRetentionAndDeletionTests.swift`
- `CleanerCore/Tests/CleanerCoreFoundationTests/ReceiptStoreHostileFixtureTests.swift`
- `MyMacCleanerTests/ReceiptHistorySessionTests.swift`
