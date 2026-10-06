# Detector contract

Rules for local evidence detectors in CleanerCore. Detectors explain storage.
They do not mutate the filesystem.

## Inputs

- A declared root from a versioned catalog (not a user-typed path string)
- Injected filesystem, clock, cancellation, diagnostics, and metrics ports
- Fixed detector identity and semantic version

`DetectorRegistry` rejects an empty registry, duplicate registration, invalid
version, unknown detector, or unsupported version.

## Outputs

Every finding carries immutable identity, provenance, detector/rule version,
logical and allocated size evidence, modification evidence, file type, declared
root, volume identity, and boundary flags when the platform exposes them.

Every scan reports a typed outcome: complete, partial, permission-denied,
cancelled, corrupt-metadata, or unsupported-layout. Missing evidence is never
presented as empty storage.

## Certainty and staleness

| Class | Behavior |
|-------|----------|
| Complete per-finding evidence | Policy may consider it, whatever the scan's overall outcome |
| Incomplete per-finding evidence | Visible; never eligible |
| Partial / denied / cancelled scan | Findings already observed are kept and judged one by one; the gap is reported |
| Unsupported / unknown layout | Protected or inspect-only |
| Changed identity between preview and execute | Per-item skipped-stale |

## Category rules

### General Mac

Six declared roots in the live Home/Disk path: user Library Caches, Logs,
Temporary, Downloads, Desktop, Documents. Packages are leaves. Generic
traversal does not cross symlink, alias, mount, volume, home, or protected-root
boundaries unless a versioned detector owns that boundary.

Traversal is breadth-first: every entry at one depth is observed before any
deeper one. An entry or folder that cannot be read is skipped with its subtree,
and the root reports the fault, so the scan reads as partial instead of
stopping. Each root is capped at depth 8, 25,000 visited entries, and 10,000
findings. A root that hits a cap or fails is recorded as an issue and the scan
moves on to the next root; only request-wide budgets and cancellation end the
whole scan.

Large files and duplicates are triage-only: never preselected, never classified
as disposable by size alone.

### AI / ML

Hugging Face, Ollama, selected-root LM Studio, and evidence-labelled MLX are
inventory. Shared blobs/layers are accounted without double-counting. No v1
plan may mutate model stores, manifests, refs, snapshots, blobs, or symlink
targets.

Vendor layouts change. Uncertain stores fail closed.

### Developer tools

`DeveloperInventoryRegistry` (version `1.0.0`) records presence for Cursor,
VS Code, Docker, and Homebrew. Workspace databases, local history, chat,
settings, credentials, MCP configuration, extensions, and unknown layouts stay
protected. Docker is read-only presence in v1 (no `docker system df` process in
the Adaptive live path). Package-manager cards explain that cleanup needs a
future tool-specific contract.

## Hostile boundaries

Fixtures cover links, mounts, permissions, hard links, shared content,
malformed metadata, cancellation, and partial failure. Tests live under
`CleanerCore/Tests/`.

## No content inspection

Detectors must not read source files, chat transcripts, credentials, or MCP
configuration in order to build a card. Presence and structural metadata only.
