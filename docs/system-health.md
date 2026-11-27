# System Health

System Health is a local inventory of selected macOS signals, presented as a convenient summary rather than a diagnostic verdict.

## What it checks

The page refreshes a small set of local observations:

- Available disk space and a root-disk status when macOS can provide it.
- A memory-use snapshot.
- Battery information on portable Macs; desktop Macs report that no battery is present.
- A startup-item count.
- The installed macOS version, shown for reference. The app does not check for updates, so this row never says macOS is up to date and does not count toward the score.

It also displays hardware, storage (under the startup disk's own name), battery, and macOS information that is available from the system.

## Health score

The score and status summarize the checks completed during the latest refresh. A warning or attention state is a prompt to inspect its specific check and decide on a response; it is not an automated repair recommendation.

A check that couldn't run, for example when `diskutil` gives no answer, says so instead of passing. It counts as zero in the score, and the summary says the result is incomplete instead of calling the Mac healthy.

## How to use it

1. Open **System Health** and let the initial check finish.
2. Read the timestamp and individual check descriptions before relying on the score.
3. Choose **Refresh** when you need a new snapshot.
4. Investigate a warning using macOS settings, Activity Monitor, or the responsible application.

## What this page does not do

System Health collects and summarizes local evidence only. It does not change storage, memory, startup configuration, updates, or hardware settings.
