# Safety Contract

MyMacCleaner is an offline-first macOS storage and memory assistant. The safety contract keeps every surface read-only except one: Adaptive Experience can move approved, re-validated files to the Trash and record a receipt. Legacy deletion, elevation, and optimizer behavior was removed, and the verifiers fail if it returns.

## Run the local contract

From the repository root, run:

```bash
bash scripts/verify-safety-contract.sh
```

The command runs the source/process audit, fixture verifier, complete SafetyContract test suite, redaction and denied-network tests, and a fail-closed LLVM production-source coverage check. It requires at least 80% executable-line coverage across every Swift file under `SafetyContract/Sources/SafetyContract`. Missing tools, profiles, source files, JSON, or malformed coverage evidence are failures.

## Disabled capability matrix

| Capability | Behavior |
|---|---|
| Permanent deletion, direct cleanup, and Empty Trash | Unavailable. The only file change is the approved, re-validated move to the Trash in Adaptive Experience, done by `FoundationTrashAdapter`. |
| Privileged shell work and administrator prompts | Unavailable; no generic command or authorization boundary is exposed. |
| Memory purge, process termination, port closing, and optimizer claims | Unavailable; memory and process views are observational. |
| Startup-item, application, and developer-tool mutation | Unavailable; inventory and system guidance remain read-only. |
| Disabled-operation networking | Unavailable; denied routes have no network capability and their recorder remains at zero requests. |

## Five fixed read-only process adapters

Only these local inventory commands are permitted by the source contract. They are the five cases of `ReadOnlyCommand` in `MyMacCleaner/Core/Services/ReadOnlyProcess.swift`, the owner of every entry in `scripts/read-only-process-allowlist.txt` and the only file in the app that may build a `Process`. Their executable paths and arguments are literals in that one file; no caller supplies a command, argument or shell string.

| Adapter | Fixed command | Purpose |
|---|---|---|
| Startup inventory | `/usr/bin/sfltool dumpbtm` | Read background-item inventory. |
| Startup inventory | `/bin/launchctl list` | Read launch-service inventory. |
| Port inventory | `/usr/sbin/lsof -iTCP -sTCP:LISTEN,ESTABLISHED -n -P` | Read listening and established TCP ports. |
| System health | `/usr/sbin/diskutil info /` | Read root-volume metadata. |
| Open-file activity | `/usr/sbin/lsof -Fn -n -P -w -b` | Mark scanned files a running process holds open as in-use, so they are never cleanup candidates. A failed, timed-out or cancelled listing fails closed: every file in a Trash-eligible root counts as open for that run, Adaptive Experience says why nothing can move, and the count-only `OPEN_FILE_ACTIVITY_UNAVAILABLE` diagnostic is logged. |

`ReadOnlyProcess` reads the output pipe to the end before it waits for the command to exit. Waiting first would hang both sides once the output fills the pipe buffer. `SC-PROCESS-DRAIN-ORDER` fails the gate when `waitUntilExit` comes before `readDataToEndOfFile` in the same `Process()` block. A command that runs past 10 seconds, or whose calling task is cancelled, is stopped and reported unavailable, so no screen waits on a stalled tool. `SC-UNLISTED-PROCESS` fails on a child process built anywhere else in the app, and `SC-PROCESS-IDENTITY` fails on any executable or argument that is not in the allowlist.

## Privacy and diagnostics

### Redacted diagnostics

Diagnostic records are typed and bounded. Paths, local names, credentials, command text, appcast bodies, receipt payloads, and raw errors are not retained or printed. Production diagnostics use only fixed event codes and counts.

### No-network disabled routes

The SafetyContract target and disabled legacy routes contain no URLSession, URLRequest, Network.framework, or URL capability. The app has no update channel (`UpdateCapability.unavailable`), and `bash scripts/verify-safety-contract.sh --diagnostics-network-only` fails if an updater, `URLSession`, Sparkle import, or appcast reference returns.

## Hosted CI and remaining evidence

`.github/workflows/safety-contract.yml` runs `bash scripts/verify-all.sh` on a `macos-26` runner with Xcode 26. That script runs `bash scripts/verify-safety-contract.sh`, followed by the CleanerCore gate, the CleanerCore source contract, both Adaptive Experience verifiers, and every verifier self-test. It has `contents: read`, uses only the official `actions/checkout` pinned to a full commit SHA with persisted credentials disabled, and has no cache, artifact, signing, notarization, release, publication, or write-permission capability.

- **First hosted run**: done. The Safety Contract workflow has passed on a recorded commit; see [RELEASE-RUNBOOK.md](RELEASE-RUNBOOK.md).
- **Full-Xcode**: the app build, unit tests, and archive pass in the PR Checks workflow, and UI tests run there as an advisory job. The manual VoiceOver, keyboard, Reduce Motion, and Increase Contrast walk is still pending.

[RELEASE-RUNBOOK.md](RELEASE-RUNBOOK.md) is the only place release status is claimed. Do not describe a gate as complete there until its own evidence exists.
