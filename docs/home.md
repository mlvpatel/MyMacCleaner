# Home & Smart Scan

Home is the local review dashboard for storage, memory, installed-app counts, permission-aware scanning, and safe navigation to detailed views.

## Dashboard

The dashboard shows current storage use, memory in use, the size of the caches, logs and temporary files found by the last scan, installed-app count (apps in /Applications and ~/Applications, the same count the Applications page shows), and a health indicator for disk and memory use. The indicator reads **Not scanned yet** until a Smart Scan completes, then shows Healthy, Fair or Needs Attention (as text and an icon) based on disk and memory use when that scan finished; the sidebar badge shows the same level. Your Downloads, Desktop and Documents folders are listed in the scan results but never counted in that figure. Values are local observations and can change while the app is open.

## Smart Scan

Smart Scan gathers a categorized storage review. Without Full Disk Access, Home first shows a Full Disk Access sheet with **Open System Settings**, **Continue with Limited Scan** and **Maybe Later**. The sheet says a limited scan reads your Desktop, Documents and Downloads folders and that macOS may ask you to allow access to each one. **Maybe Later** (or Escape) closes the sheet without scanning. After you choose **Continue with Limited Scan**, Home (and the menu bar Scan) stops asking for the rest of the session. If you grant Full Disk Access while the prompt is open, the prompt closes and the scan starts when you come back to the app.

1. Select **Smart Scan**.
2. Wait for the scan to finish, or select **Cancel** to stop it. Leaving the page while a scan runs stops it too; when you come back the page says the last scan stopped. A stopped or failed scan keeps the results of the last finished scan on screen, so it never looks like an empty result. The scan cannot know in advance how much the folders hold, so it shows an activity indicator rather than a percentage.
3. Expand a category to see its largest items and reveal them in Finder. Each item's **Show in Finder** button is always shown, so the keyboard and VoiceOver can reach it. The results card has no checkboxes or selection.
4. Select **Open in Experience** to review eligible cache items. The [Adaptive Experience](adaptive-experience.md) is the only place where MyMacCleaner moves a file, to the Trash, after you approve it.

Home, Disk Cleaner and the Adaptive Experience share one scan: whichever page scans, the other two show the same results, so the six folders are read once and the totals agree.

If macOS would not let the scan read a folder, Home names it and offers **Open Permissions**; folders read only in part are named too, and any item the scan found but could not list is counted. A scan that finds nothing says **Nothing Found** and whether every folder could be read, so missing access never looks like an empty disk.

## Quick actions

- **Trash review** explains the safety boundary for reviewing local storage.
- **Memory Guide** opens the Performance page at its read-only guidance, below the current CPU, memory, swap, and timestamp context.
- **Large Files** opens Space Lens with its size filter set to items over 100 MB. Space Lens does not scan on its own: when no scan is loaded, its start screen says the filter is on and offers **Scan Home Folder**.

Quick actions and the other links on Home open in the window you used, even when two windows are open.

## What this page does not do

Home prepares evidence for review and routes to observational views. It does not alter local files, memory, processes, or macOS settings.
