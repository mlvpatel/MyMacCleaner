# Startup Items

Startup Items is an offline, read-only inventory of login-related items and launch-agent evidence on your Mac.

## What it inventories

The scan reports available background/login-item information, user and system launch-agent files, and running evidence where macOS exposes it. Each row can show a name, label, developer when available, type, status, and a Finder reveal action.

System items are hidden by default and can be included in the view for investigation. The summary cards count user items, enabled and disabled states reported by the system, and currently running evidence.

## How to use it

1. Open **Startup Items** and select **Scan**.
2. Search by name, label, or developer, then filter by item type or sort order.
3. Reveal a row in Finder when you need to inspect its local source.
4. Select **Open Login Items Settings** to open macOS’s documented Login Items settings pane and make any desired changes there.
5. Refresh the inventory after a macOS settings change.

## Interpreting an item

Treat unknown entries as evidence to investigate, not a reason to act immediately. Check the developer, label, associated application, and Finder location before deciding what it represents. Apple system items should be reviewed especially carefully.

## Phase-0 limitation

This feature scans, filters, sorts, reveals, and opens the fixed macOS Login Items settings destination. It does not alter startup entries, launch services, processes, or files.
