# System Health

System Health is a local inventory of selected macOS signals, presented as a convenient summary rather than a diagnostic verdict.

![System Health](/MyMacCleaner/screenshots/system_health/system_health.png)

## What it checks

The page refreshes a small set of local observations:

- Available disk space and a root-disk status when macOS can provide it.
- A memory-use snapshot.
- Battery information on portable Macs; desktop Macs report that no battery is present.
- A startup-item count.
- A macOS update-status check.

It also displays hardware, storage, battery, and macOS information that is available from the system.

## Health score

The score and status summarize the checks completed during the latest refresh. A warning or attention state is a prompt to inspect its specific check and decide on a response; it is not an automated repair recommendation.

## How to use it

1. Open **System Health** and let the initial check finish.
2. Read the timestamp and individual check descriptions before relying on the score.
3. Choose **Refresh** when you need a new snapshot.
4. Investigate a warning using macOS settings, Activity Monitor, or the responsible application.

## Phase-0 limitation

System Health collects and summarizes local evidence only. It does not change storage, memory, startup configuration, updates, or hardware settings.
