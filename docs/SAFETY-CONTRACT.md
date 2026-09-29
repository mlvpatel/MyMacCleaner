# Safety Contract

MyMacCleaner is an offline-first macOS storage and memory assistant. Phase 0 is a safety freeze: it removes legacy mutation, elevation, and optimizer behavior before reviewed cleanup plans and Trash-first execution are built in later phases.

## Run the local contract

From the repository root, run:

```bash
bash scripts/verify-safety-contract.sh
```

The command runs the source/process audit, fixture verifier, complete SafetyContract test suite, redaction and denied-network tests, and a fail-closed LLVM production-source coverage check. It requires at least 80% executable-line coverage across every Swift file under `SafetyContract/Sources/SafetyContract`. Missing tools, profiles, source files, JSON, or malformed coverage evidence are failures.

## Disabled capability matrix

| Capability | Phase-0 behavior |
|---|---|
| Permanent deletion, direct cleanup, and Empty Trash | Unavailable; the app provides inventory and explanation only. |
| Privileged shell work and administrator prompts | Unavailable; no generic command or authorization boundary is exposed. |
| Memory purge, process termination, port closing, and optimizer claims | Unavailable; memory and process views are observational. |
| Startup-item, application, and developer-tool mutation | Unavailable; inventory and system guidance remain read-only. |
| Disabled-operation networking | Unavailable; denied routes have no network capability and their recorder remains at zero requests. |

## Five fixed read-only process adapters

Only these local inventory commands are permitted by the source contract. Their executable paths and arguments are fixed in code; no caller supplies a command or shell string.

| Adapter | Fixed command | Purpose |
|---|---|---|
| Startup inventory | `/usr/bin/sfltool dumpbtm` | Read background-item inventory. |
| Startup inventory | `/bin/launchctl list` | Read launch-service inventory. |
| Port inventory | `/usr/sbin/lsof -iTCP -sTCP:LISTEN,ESTABLISHED -n -P` | Read listening and established TCP ports. |
| System health | `/usr/sbin/diskutil info /` | Read root-volume metadata. |
| Open-file activity | `/usr/sbin/lsof -Fn -n -P -w -b` | Mark scanned files a running process holds open as in-use, so they are never cleanup candidates. A failed listing marks nothing open. |

## Privacy and diagnostics

### Redacted diagnostics

Diagnostic records are typed and bounded. Paths, local names, credentials, command text, appcast bodies, receipt payloads, and raw errors are not retained or printed. Production diagnostics use only fixed event codes and counts.

### No-network disabled routes

The SafetyContract target and disabled legacy routes contain no URLSession, URLRequest, Network.framework, or URL capability. Update networking is outside this disabled-route boundary and is not evidence that a disabled action can communicate.

## Hosted mirror and pending evidence

`.github/workflows/safety-contract.yml` mirrors the exact local command on `macos-14`. It has `contents: read`, uses only `actions/checkout@v4` with persisted credentials disabled, and has no cache, artifact, signing, notarization, release, publication, or write-permission capability.

Two gates remain intentionally pending:

- **Full-Xcode**: run the app and UI test command recorded in Phase 0 validation on a runner with full Xcode.
- **First hosted run**: after the authorized private push, confirm the new workflow executes the same local command and passes.

Do not describe either gate as complete until its own current evidence exists.
