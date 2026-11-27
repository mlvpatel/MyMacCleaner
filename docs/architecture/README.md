# Architecture diagrams

Interactive, standalone HTML diagrams of MyMacCleaner, generated with
[archify](https://github.com/tt-a1i/archify) 3.2 from the November 2026 source.
Open any `.html` file in a browser; each works offline and has light and dark themes.

| Diagram | Type | What it shows |
|---|---|---|
| [Cleanup trust pipeline](trash-trust-pipeline.html) | Workflow | Every gate from scan to Trash: policy, review plan, approval, fresh revalidation, journaled move, receipt |
| [Approve to Trash](approve-move-to-trash.html) | Sequence | The real call chain when a user approves the displayed plan, with refusal returns and per-item outcomes |
| [Cleanup item lifecycle](cleanup-item-receipt.html) | Lifecycle | Item and receipt states, admission limits, restart reconciliation, retention |
| [Local evidence flow](local-evidence.html) | Data flow | Where on-device evidence goes: sources, scan and policy transforms, receipts, views, Trash, and no network egress |
| [CleanerCore trust types](cleanercore-trust-types.html) | Class | The Swift types behind the single mutation path and the internal constructors that stop fabrication |
| [Repository map](repository-modules.html) | Tree | Tracked folders and modules, each with a one-line purpose |
| [System architecture](mymaccleaner-system.html) | Architecture | App shell, view models, trust session, CleanerCore targets, host processes and the files the app touches, with the single Trash path highlighted |

The workflow, sequence, data flow, class and architecture diagrams cite source lines that archify
verified against current `main` as of November 2026. The public history may use different hashes,
and later commits may shift the cited line numbers. The lifecycle diagram lists
its sources in an on-page card. Diagrams describe the code at that point; regenerate them after
architectural changes.

## Regenerate

Each diagram's source is the `.archify.json` file beside it. From the repository root, with
archify checked out locally:

```bash
node <archify>/archify/bin/archify.mjs finalize workflow docs/architecture/trash-trust-pipeline.archify.json docs/architecture/trash-trust-pipeline.html --repo-root . --quality showcase
```

Use the matching type (`sequence`, `lifecycle`, `dataflow`, `class`, `tree`, `architecture`) for the other files. Source
verification needs a checkout whose `origin` remote matches the `meta.repository.url` in the
candidate.
