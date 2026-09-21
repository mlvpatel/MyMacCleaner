# Threat model

Assets, boundaries, and STRIDE controls for MyMacCleaner v1. Verification
commands are the local gates that exist in this checkout. Hosted CI, full Xcode,
and Developer ID evidence are **pending** unless a later document records a
specific run.

## Assets

| Asset | Why it matters | Where it lives |
|-------|----------------|----------------|
| Local filesystem identity | Wrong mutation deletes the wrong object | Findings, `ReviewPlanTarget`, revalidator |
| Model stores and developer state | Irreplaceable or tool-owned | Policy semantic owners; inventory-only cards |
| Receipt journal | Truth after interruption | Application Support store |
| Diagnostics | Paths and names must not leak | `RedactingDiagnostic`, SafetyContract |
| Signing material | Direct distribution | Must never be in the repository |

## Boundaries

| Boundary | Control |
|----------|---------|
| UI to CleanerCore | Projection cannot widen roots or eligibility |
| Plan to executor | Only `MoveToTrash` from an approved, unexpired plan |
| Executor to filesystem | Fresh identity/topology check; stale then skip |
| App to process | Four read-only adapters; no user-controlled shell |
| Trust pipeline to network | No URLSession in scan/plan/execute/receipt |
| Docs to release claims | Status matrix in [RELEASE-RUNBOOK.md](RELEASE-RUNBOOK.md) |

## STRIDE register

| ID | Category | Component | Severity | Control | Verify |
|----|----------|-----------|----------|---------|--------|
| T-SAFE-ELEV | Elevation of Privilege | Privileged shell / AppleScript | critical | Phase 0 freeze; `DisabledOperationGateway` | `bash scripts/verify-safety-contract.sh` |
| T-SAFE-RM | Tampering | `rm`, Empty Trash, purge | critical | Mutation APIs removed; typed Trash only | SafetyContract source denylist |
| T-CORE-SCOPE | Elevation of Privilege | Detector registry | high | Shipped, versioned detectors only | CleanerCore registry tests |
| T-CORE-LINK | Tampering | Symlink / mount / home | high | Topology stops; incomplete is not eligible | General-Mac hostile fixtures |
| T-AIML-MUT | Tampering | HF / Ollama / MLX stores | critical | Semantic owner `modelStore` ineligible | AIML no-mutation tests |
| T-DEV-CONTENT | Information Disclosure | Editor chats, credentials, MCP | high | Presence-only inventory; no content read | `DeveloperInventoryContractTests` |
| T-PLAN-STALE | Spoofing | Reused approval | high | Digest + session + expiry invalidation | `PlanInvalidationPropertyTests` |
| T-EXEC-TOCTOU | Tampering | Changed target before Trash | critical | `FreshEvidenceRevalidator` | `TrashExecutionHostileFixtureTests` |
| T-EXEC-API | Elevation of Privilege | Second Trash API | critical | Sole `FoundationTrashAdapter` | contract source gate |
| T-REC-LEAK | Information Disclosure | Receipt payload in logs | high | Opaque IDs; redacted diagnostics | receipt privacy tests |
| T-UX-AUTH | Elevation of Privilege | Mode picker | high | Presentation-only modes | `AdaptiveExperienceProjectionTests` |
| T-REL-CLAIM | Spoofing | Notarization / Gatekeeper prose | high | This register + release runbook | Do not claim pending gates |

## Residual risks (named, not closed)

- App sandbox is off in the current entitlements.
- No update channel exists; Sparkle and `URLSession` were removed from the app target (enforced by `SC-UPDATE-CAPABILITY`).
- Space Lens, Duplicates, Orphaned Files, and Browser Privacy still use evidence-only legacy scanners outside CleanerCore (see C4 L4). `FileScanner` was retired.
- Full-Xcode UI, VoiceOver, and XCUITest are not proven on this machine.
- No hosted GitHub Actions run is recorded as passed from this session.

## Related documents

- [C4.md](C4.md)
- [SAFETY-CONTRACT.md](SAFETY-CONTRACT.md)
- [DETECTOR-CONTRACT.md](DETECTOR-CONTRACT.md)
- [RECOVERY.md](RECOVERY.md)
- [../SECURITY.md](../SECURITY.md)
