# Disk Cleaner & Browser Privacy

Disk Cleaner and Browser Privacy are local review surfaces for storage categories and browser-data evidence.

## What it shows

The pages organize scan results by the folder they came from: Caches, Logs, Temporary files, Downloads, Desktop and Documents. Downloads, Desktop and Documents are your own folders and are listed for review only. Each item shows its path, size estimate and the modification date the scan observed, and the full list can be sorted by size, date or name. Browser Privacy can show browser-related categories when those locations are readable. When macOS will not let it read a browser's data (Safari's needs Full Disk Access), Browser Privacy names that browser and offers **Open Permissions**, and an empty list then says only that nothing was found in the data it could read, without a green check.

Scan results are review material. Some values depend on macOS permissions and may be incomplete when access is limited: after a scan, the page names any folder it could not read (with **Open Permissions**) or could read only in part, and counts any item it found but could not list. An empty result says **Nothing Found** rather than claiming the disk is clean. While scanning, the page shows an activity indicator with Cancel instead of a percentage the scan cannot measure. Leaving the page while a scan runs stops it; when you come back the page says the last scan stopped. A scan you cancel, that stops when you leave, or that fails keeps the results of the last finished scan on screen, so it never reads as **Nothing Found**; a failed scan also says why. Browser Privacy runs one scan at a time and stops it when you leave; its last results, and the Disk Cleaner tab you chose, stay when you switch to another section and back.

## How to use it

1. Start a scan from Home or Disk Cleaner. Without Full Disk Access, both pages say before the scan that it reads your Desktop, Documents and Downloads folders and that macOS may ask you to allow access to each one. Both pages, and the Adaptive Experience, show the same latest scan, so a scan started on one page fills the others.
2. Review category names, paths, and size estimates.
3. Open a category's full list to search and sort its items; a search that matches nothing says so and offers **Clear Search**. The pages have no checkboxes, Select All or cleanup button.
4. Select **Open in Experience** when you want eligible cache items reviewed for a move to the Trash; only the Adaptive Experience can move files.
5. Grant macOS file access only when you want a more complete local scan.

## What this page does not do

These pages present storage evidence only. They do not delete files, empty Trash, change browser data, run cleanup scripts, or alter system folders.
