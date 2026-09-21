# Performance

The Performance page is an offline, read-only view of current CPU and memory evidence.

![Performance](/MyMacCleaner/screenshots/performance/performance.png)

## What it shows

- Current CPU utilization, refreshed while the page is active.
- A timestamped memory snapshot: used, free, total, active, wired, compressed, cached/inactive, and purgeable memory.
- Swap usage when macOS exposes it.
- An explicit unavailable state when a value cannot be read.

macOS manages memory itself. These figures are context for deciding whether to close, pause, or investigate work in other applications; they are not a diagnosis of a problem on their own.

## How to use it

1. Open **Performance** and wait for the first observation timestamp.
2. Compare memory and swap values while the workload you care about is running.
3. Refresh your understanding over a few observations rather than reacting to one value.
4. Use the information alongside Activity Monitor or the relevant application when you need to change a workload.

## Phase-0 limitation

This page observes CPU, memory, and swap state only. It does not alter memory, run maintenance actions, control processes, or request an administrator password.
