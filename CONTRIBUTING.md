# Contributing to MyMacCleaner

Thanks for contributing.

MyMacCleaner is developed in the open at
[github.com/mlvpatel/MyMacCleaner](https://github.com/mlvpatel/MyMacCleaner).
Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md),
not in public issues. [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) sets the
community standards. `CLAUDE.md` describes the current architecture and the
safety contract.

## License of contributions

By submitting a pull request or other contribution, you agree to license your
contribution under GNU AGPLv3 or later, the same license as the project
([LICENSE](LICENSE)).

## Local gates

From the repository root, run what CI runs before you push:

```bash
bash scripts/verify-all.sh          # the Safety Contract workflow, step for step
bash scripts/verify-all.sh --fast   # source contracts and self-tests only; skips Swift tests and coverage
```

`verify-all.sh` runs the SafetyContract tests and coverage gate, the CleanerCore
tests with 80% line coverage per production target, the CleanerCore source
contract, both Adaptive Experience verifiers, and every verifier self-test. A
failure starts with a rule ID; [docs/VERIFIER-RULES.md](docs/VERIFIER-RULES.md)
explains each one.

The PR Checks workflow also runs these, which need full Xcode:

```bash
xcodebuild test -project MyMacCleaner.xcodeproj -scheme MyMacCleaner \
  -destination 'platform=macOS' -only-testing:MyMacCleanerTests \
  -enableCodeCoverage YES -resultBundlePath build/TestResults.xcresult
bash scripts/check-app-coverage.sh build/TestResults.xcresult   # app coverage ratchet
swiftlint lint                                                  # CI pins SwiftLint 0.65.1
```

Delete `build/TestResults.xcresult` before running the tests again. PR Checks
also fails on Swift files over 800 lines and on `#unavailable`.

In a sandbox where the default Swift module cache is not writable, set
`CODEX_SANDBOX=1`. The test runners (`run-safety-tests.sh`,
`run-cleanercore-tests.sh`) then keep their module caches under `$TMPDIR` and
pass `--disable-sandbox` to SwiftPM.

Architecture and trust docs:

- [docs/C4.md](docs/C4.md)
- [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md)
- [docs/DETECTOR-CONTRACT.md](docs/DETECTOR-CONTRACT.md)
- [docs/RECOVERY.md](docs/RECOVERY.md)
- [docs/PRIVACY.md](docs/PRIVACY.md)
- [docs/RELEASE-RUNBOOK.md](docs/RELEASE-RUNBOOK.md)

## How to contribute

1. Create a branch from `main`.
2. Add tests for trust-core or safety behavior you change.
3. Run the local gates above (`bash scripts/verify-all.sh` at least).
4. Do not restore `FileScanner` mutation, privileged shell, `rm`, Empty Trash,
   or memory purge.
5. Do not commit secrets, signing material, or `.env` files.
6. Open a pull request. CI runs the PR Checks and Safety Contract workflows on
   every pull request; both should pass before merge.

## Full Xcode

App scheme build, UI tests, and assistive-technology walks require full Xcode
on macOS. Command Line Tools success is not a substitute. Use Xcode 26 or
later. CI tests with Xcode 26 (the newest 26.x on GitHub's `macos-26` runners).
