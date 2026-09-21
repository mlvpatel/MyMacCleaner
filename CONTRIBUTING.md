# Contributing to MyMacCleaner

Thanks for contributing.

This repository is a private development tree that is being prepared for
open-source review. Maintainer identity is a **neutral placeholder** until
publication. Use [SECURITY.md](SECURITY.md) for vulnerability reports and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community standards.

## License of contributions

By submitting a pull request or other contribution, you agree to license your
contribution under GNU AGPLv3 or later, the same license as the project
([LICENSE](LICENSE)).

## Local gates (Command Line Tools)

From the repository root:

```bash
bash scripts/verify-safety-contract.sh
bash scripts/verify-adaptive-experience.sh
CODEX_SANDBOX=1 bash scripts/verify-cleanercore.sh
```

These prove SafetyContract, Adaptive catalog/identifier contracts, CleanerCore
tests, and 80% line coverage per production target. They do **not** prove a
full-Xcode app build, XCUITest, VoiceOver, signing, notarization, or hosted CI.

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
3. Run the local gates above.
4. Do not restore `FileScanner` mutation, privileged shell, `rm`, Empty Trash,
   or memory purge.
5. Do not commit secrets, signing material, or `.env` files.
6. Open a pull request. Hosted GitHub Actions is not claimed green until a
   recorded run exists.

## Full Xcode

App scheme build, UI tests, and assistive-technology walks require full Xcode
on macOS. Command Line Tools success is not a substitute.
