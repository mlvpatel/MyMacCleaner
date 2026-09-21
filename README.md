<div align="center">

# 🧹 MyMacCleaner

**A safety-first macOS maintenance app — read-only by design.**

See what's using your disk and memory, inventory local AI/ML and developer-tool
storage *without touching it*, and move only approved, re-validated items to the
Trash — always with a receipt.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI%20·%20Liquid%20Glass-8A2BE2)
![License](https://img.shields.io/badge/license-AGPL--3.0-green)

</div>

---

MyMacCleaner is **not** a one-click optimizer. Every destructive action is typed,
allow-listed, and Trash-first. Privileged shell, `rm`, Empty Trash, and memory
purge are disabled at the architecture level — not merely hidden.

## ✨ Highlights

- **Liquid Glass UI** — native translucent design on macOS 26, with a material
  fallback on macOS 14–15.
- **Three explanation depths** — the same evidence in a *Guided*, *Standard*, or
  *Technical* view, so newcomers and power users each get the right detail.
- **Read-only inventory** — scans, groups, and visualizes storage and memory
  without changing anything.
- **Trash-first execution** — the only mutation is an approved, digest-bound plan
  moved to the Trash, re-validated item-by-item, and always recoverable.
- **Menu-bar monitor** — live CPU / RAM / Disk with four display modes.

## 🖥 Features

| Surface | What it does |
|---------|--------------|
| Home / Smart Scan | Live storage scan through CleanerCore across six general-Mac roots |
| Disk Cleaner | Category review of caches, logs, and temporary data |
| Space Lens | Read-only storage map (sidebar and Disk Cleaner tab); cancellable, 500,000-entry cap |
| Duplicates | Hash-based duplicate finder with cancellation |
| Orphaned Files | Review-only leftovers from removed apps |
| Performance | Review timestamped memory and process observations |
| Port Management | Inspect fixed network connection inventory, filter, and refresh |
| System Health | Review startup-item inventory and system stats |
| Applications | Read-only app inventory with Homebrew cask listing |
| AI/ML inventory | Local model-store parsers (Hugging Face, Ollama, LM Studio, MLX) |
| Trash execute | Moves only the approved, digest-bound cache plan to Trash, re-validated per item, with a receipt |

## 🎨 Design & UI

- **SwiftUI** throughout, MVVM with Swift actors for services.
- **Adaptive Experience** screen presents evidence at three depths and walks a
  clear review → approve → move-to-Trash → receipt flow.
- **Sidebar navigation** across every surface, plus a real-time menu-bar item.
- **Accessibility-minded:** honors Reduce Motion and Increase Contrast; keyboard
  and VoiceOver friendly.
- **Localization:** English (String Catalogs; more locales can be added later).

## 🔒 Safety model

Scanning and evidence live in the `CleanerCore` package, fully separated from any
mutation. The single destructive capability is a move-to-Trash of an approved,
digest-bound plan that is re-validated per item at execution time and recorded in
a private local receipt. Empty Trash, permanent delete, privileged/admin commands,
memory purge, and process termination are disabled behind a `SafetyContract`
gateway. See [docs/SAFETY-CONTRACT.md](docs/SAFETY-CONTRACT.md) and
[docs/THREAT-MODEL.md](docs/THREAT-MODEL.md).

## 📸 Screenshots

_Add screenshots under `docs/screenshots/` and link them here._

## Requirements

- macOS 14.0 or later (Apple Silicon or Intel)
- Xcode 26 or later to build the app, run UI tests, and archive

## Build & run

```bash
open MyMacCleaner.xcodeproj
```

Then build and run the `MyMacCleaner` scheme (⌘R).

## Testing

```bash
xcodebuild test -project MyMacCleaner.xcodeproj -scheme MyMacCleaner \
  -destination 'platform=macOS' -only-testing:MyMacCleanerTests
bash scripts/verify-safety-contract.sh
bash scripts/verify-cleanercore.sh
```

CleanerCore holds ≥80% line coverage — see [docs/COVERAGE.md](docs/COVERAGE.md).

## Updates

There is no auto-update channel. Install new versions manually from a reviewed
release.

## Signing

`Config/Signing.xcconfig` signs ad hoc by default so anyone can build. For a
Developer ID build, copy `Config/Signing.local.xcconfig.example` to
`Config/Signing.local.xcconfig` (git-ignored) and set your team and identity.

## Contributing & security

- [CONTRIBUTING.md](CONTRIBUTING.md) · [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) · [SECURITY.md](SECURITY.md)
- Architecture: [docs/C4.md](docs/C4.md), [docs/DETECTOR-CONTRACT.md](docs/DETECTOR-CONTRACT.md), [docs/RECOVERY.md](docs/RECOVERY.md), [docs/PRIVACY.md](docs/PRIVACY.md)

## License

GNU Affero General Public License v3.0 or later — see [LICENSE](LICENSE).
