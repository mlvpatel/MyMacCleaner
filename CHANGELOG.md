# Changelog

All notable changes to MyMacCleaner will be documented in this file.

## [Unreleased]

<!-- Add your changes here during development. This section will be used for the next release. -->
<!-- Format: - [type] Description -->
<!-- Types: added, changed, fixed, removed -->
<!-- DRAFT for 1.0.0: summary of the rewrite since 0.1.3. Edit before release. -->

### 1.0 rewrite (since 0.1.3)

- [changed] Rebuilt as a safety-first app: privileged shell, `rm`, Empty Trash, memory purge, process termination, app uninstall and cleanup scripts are disabled behind a `SafetyContract` gateway
- [added] `CleanerCore` package: local evidence, conservative policy, digest-bound review plans, a revalidated Trash executor and receipts
- [added] General-Mac evidence for six locations: Library Caches, Logs, Temporary, Downloads, Desktop and Documents
- [added] Adaptive Experience with Guided, Standard and Technical views and a review, approve, move-to-Trash, receipt flow
- [added] Private local receipts with recovery guidance and bounded history (90 days, 500 receipts)
- [added] Read-only AI/ML model inventory (Hugging Face, Ollama, LM Studio, MLX) and developer-tool presence (Cursor, VS Code, Docker, Homebrew)
- [added] Read-only memory and workload coach
- [changed] Disk Cleaner, Space Lens, Duplicates, Orphaned Files, Performance, Applications, Port Management, System Health and Startup Items are read-only inventories
- [changed] English-only String Catalogs (Italian and Spanish removed, along with the language picker)
- [removed] Sparkle auto-update and the appcast: the app has no `URLSession` and no update channel; install new versions from a reviewed release

### Pre-release QA fixes

- [fixed] Scans no longer stop at the first unreadable folder or drop the remaining locations when one fails; gaps are reported as a partial scan
- [fixed] Scans walk each location shallow-first, so one large deep folder cannot hide the rest under the per-location cap
- [fixed] Live scans use the real clock, so the inactivity rule for the named cache can pass
- [fixed] Receipt file names no longer exceed the macOS file-name limit for long item paths
- [fixed] Execute re-checks policy on a fresh scan (including open files), refuses hardlinked files, and allows only regular files inside the named cache scope
- [fixed] A Trash move without a returned location is recorded as moved; a run that never started is reported as refused
- [fixed] The dashboard and review sheet show the first 50 evidence items plus a count of the rest, so large scans no longer stall the UI
- [fixed] The loading-dots animation no longer leaks a repeating timer each time it appears
- [fixed] The receipt history lock file is no longer read as an unreadable receipt, which made the app refuse new cleanups one receipt early
- [fixed] A crash while writing a receipt, or a Finder `.DS_Store` inside it, no longer turns the receipt into a permanently unreadable one that counts toward the 50-receipt cleanup block
- [fixed] The receipt history lock now lives beside the receipts folder (`MyMacCleaner/receipts.lock`), created only after that folder is locked down, and the app no longer builds its own copy of the receipts path
- [fixed] Duplicates stops at 500,000 files and says so, Cancel now stops in the middle of hashing a large file, a file that fails to read is left out instead of matched on a partial hash, and hard-link checks no longer slow down quadratically
- [fixed] Space Lens no longer rebuilds every bubble on each hover in folders with more than 20 items, which could leave a bubble highlighted after the pointer left
- [fixed] Space Lens works with the keyboard and VoiceOver: list rows are buttons that read the item's name and size and open folders, the Back, Scan again, Show in Finder and filter controls have names, and the details bar follows the focused row
- [fixed] The Adaptive permission-help sheet has a Close button and closes with Escape; before, the only way out was to quit the app
- [fixed] Adaptive Opportunities and review list only the items the plan would move, by name, folder, size and recovery path, and count the other findings instead of listing hex identities (shown only in Technical); the confirmation now reads, for example, "Move 3 items (12.4 MB) to the Trash?" and names the items; a card opens review scrolled to its item
- [fixed] Moving items to the Trash shows a labelled progress view on the dashboard and in review, VoiceOver announces the start, a counted finish ("Moved 12, skipped 2, failed 0.") or why a run was refused, and a summary with View receipt replaces the repeated per-item lines; the disabled Refresh explains why
- [fixed] Recovery receipts show each receipt's own status and recovery note, newest first, with its date; before, recovery notes could be paired with the wrong receipt and status was never shown
- [changed] Switching between Guided, Standard and Technical no longer freezes the window on a large scan: the evidence projection is built once per scan, off the main thread, and each finding's identity is encoded once
- [changed] The app target builds with zero concurrency warnings (all 45 would be errors in Swift 6 mode)
- [changed] Large scans finish about 3x faster (result sorting no longer re-encodes every item per comparison)
- [removed] Obsolete Mac App Store submission guide (Developer ID distribution only)
- [changed] Home, Disk Cleaner, Browser Privacy, Duplicates and Orphaned Files are read-only in every sense: no checkboxes, Select All, keeper or "Review" button that only showed a "coming later" notice. Each list ends with **Open in Experience**, the only place files can move
- [changed] Sidebar, Disk Cleaner, Browser Privacy, Duplicates, Orphaned Files and Permissions copy describes an inventory instead of promising to clean, remove or optimize
- [fixed] The Disk Cleaner detail sheet always shows the current scan results instead of a stale copy
- [fixed] Desktop, Documents and Downloads are no longer labelled "Old Downloads, files older than 30 days" or counted as junk: each scanned folder has its own category, personal folders are marked review only, and the user temp folder is called "Temporary files"
- [fixed] Home's "Junk Files" tile is now "Caches, Logs & Temp" and never counts personal folders
- [fixed] Scan results show the modification date the scan observed instead of "Unknown", so date sorting works
- [fixed] Home and Disk Cleaner scans no longer show progress stuck at 0 % (and Browser Privacy a fixed 50 %): they show an activity indicator with a caption, and Home now has a Cancel button
- [fixed] The menu bar Scan button switches to Home and starts Smart Scan (its request was posted but never observed), and Open MyMacCleaner reopens the main window after it was closed
- [removed] The Settings "Launch at login" toggle, which saved a value nothing read; registering a login item would be a second system change the safety contract does not allow
- [fixed] The sidebar badge no longer always says "System healthy" in green: it shows the Home health level from the last Smart Scan as text and an icon, reads "Not scanned yet" before one, and no longer reacts to hover
- [fixed] Folders a Home or Disk Cleaner scan could not read are named with a link to Permissions, folders read only in part are named too, and an empty result says "Nothing Found" instead of "Your Disk is Clean! Your Mac is running efficiently."
- [fixed] Reduce Motion is honoured everywhere, not only in Adaptive Experience: pages appear without the slide, cards and buttons no longer scale on hover or press, the scan pulse stops, toasts and prompts fade in instead of sliding or zooming, and tab and segment selection no longer glides
- [fixed] Light appearance, the macOS default, no longer hides card outlines, meter and ring tracks, hover and selection fills, the scan Cancel button or the search field and filter menu outlines; on macOS 14 and 15 the glass turns solid with Reduce Transparency and gets a thicker outline with Increase Contrast
- [fixed] The sidebar works without a pointer: it is a list that the arrow keys, Full Keyboard Access, Switch Control and VoiceOver move through and that reports the selected section, so Adaptive Experience, the only path to the Trash, can be reached from the keyboard
- [added] A Go menu that switches sections, with Command-1 to Command-9 for the first nine
- [fixed] Expandable rows in Home, Disk Cleaner, Browser Privacy, Duplicates, Orphaned Files, Startup Items and Permissions, and the Duplicates file-type filters, are buttons the keyboard and VoiceOver can press, and expandable rows say whether they are expanded; the custom glass buttons take their pressed look from the button itself and show one shared focus ring
- [fixed] A refused Trash run now says why: another MyMacCleaner window is using receipt history, too many earlier runs need attention, or history could not be opened. The Receipts sheet says history is unavailable, and why, instead of showing an empty list
- [fixed] If a receipt cannot be saved after items were moved, the app says the receipt is incomplete and the Receipts sheet lists where each moved item sits in the Trash for the rest of the session; before, this looked like an ordinary partial run
- [fixed] Startup Items, Port Management, System Health and the open-file check no longer wait forever on a stalled system tool: a tool still running after 10 seconds is stopped and its data shown as unavailable
- [fixed] Leaving Port Management while it refreshes now stops its `lsof` read instead of leaving it running in the background
- [fixed] When the open-file check cannot run (`lsof` fails, times out or is stopped), Adaptive Experience no longer treats it as "nothing is open": nothing can move to the Trash that time, a banner says why, and a count-only diagnostic is logged
- [fixed] The menu bar, Home, System Health and Performance read memory from one source (Active + Wired + Compressed) and judge CPU, memory and disk against the same thresholds, so one reading gets the same color, icon and level everywhere; at 85 % memory the menu bar no longer shows red while Home shows Fair, and the menu bar memory line shows an icon and a level from the same reading instead of a dot that could disagree with its text
- [fixed] Turning the menu bar monitor off and on no longer leaves an extra stats loop running each time
- [changed] The menu bar monitor does less work on every 2-second tick: one stats update instead of four, the status item is redrawn only when its numbers change, disk use is read off the main thread at most every 30 seconds instead of five times per popover redraw, sampling pauses in Icon mode while the popover is closed, and its timer (and the Performance timer) lets macOS coalesce wakeups
- [changed] Hovering in Space Lens updates only the highlight, the list rows and the details bar instead of re-rendering and re-sorting the whole page (and the Disk Cleaner view around it), and the scanned tree is now immutable
- [changed] Space Lens releases a finished scan two minutes after you leave it, instead of keeping up to 500,000 items in memory for the rest of the session; coming back sooner keeps it, and afterwards the page offers a new scan
- [changed] Duplicates and Orphaned Files keep their filtered, sorted lists instead of rebuilding them several times per redraw, lower-case each name once per scan, wait for a short pause in typing before searching, and build long lists lazily, so typing in search no longer stalls on large results
- [fixed] Duplicates no longer downloads iCloud files to compare them: files whose contents are not on this Mac are left out, and the header says how many
- [fixed] Folder sizes in Applications, Orphaned Files, Browser Privacy and the developer inventory come from one walk that stops at 500,000 entries and as soon as the scan is cancelled, never follows a symlink out of the folder, and counts hidden files; before, there were four copies, three with no limit and three that kept walking after Cancel
- [fixed] Toasts come from one shared presenter: success and info messages hide after 3 seconds, errors and safety notices stay until dismissed, VoiceOver announces each one, "Learn why" is a link that opens Adaptive Experience, and the dismiss button has a name; Startup Items no longer hides a newer toast early
- [fixed] The custom tab and segment pickers tell VoiceOver which option is selected, the Startup Items "System items" switch has a name, and the Startup Items and Applications filter and sort menus use native check marks; the unused second button style is gone
- [fixed] Every reachable sheet closes with Escape: the Home Full Disk Access prompt is a real sheet with Maybe Later as its cancel action, and the Disk Cleaner category sheet's close button has a name and answers Escape, as does Cancel on the scan overlay
- [fixed] Before a limited scan, the Home prompt says it reads Desktop, Documents and Downloads and that macOS may ask for access, and the app gives macOS a plain reason for each of those folders
- [fixed] Home and Disk Cleaner count any found item they cannot list and say how many, instead of skipping it silently; a progress update or result from a cancelled Home, Disk Cleaner, Duplicates or Orphaned Files scan can no longer land in the scan that replaced it
- [changed] Home, Disk Cleaner and Adaptive Experience share one scan: a Smart Scan, a Disk Cleaner scan or an Experience refresh fills all three, so the six folders are read once instead of up to three times and the pages show the same totals. Moving items to the Trash still checks every item on its own fresh scan
- [changed] Adaptive Experience no longer rescans on every visit: it loads once, after you close the welcome sheet (so no folder prompt appears behind it), and loads again only when its evidence is more than five minutes old or another page scanned since. Leaving the page stops a load but never a move to the Trash
- [fixed] Leaving Home, Disk Cleaner, Duplicates or Orphaned Files while a scan runs still stops it, and the page now says so when you come back instead of looking as if nothing had been scanned
- [fixed] Leaving Applications stops app discovery and size analysis, and Browser Privacy stops its scan and no longer runs two at once when Rescan is pressed during a scan; stopped work no longer reports itself as finished
- [changed] Launching the app no longer runs `lsof`, the System Health checks (including `diskutil`) or the Permissions folder probes: each runs the first time you open its page, and Permissions reads folders off the main thread so a macOS folder prompt no longer freezes the window
- [fixed] Choosing Analyze Apps while Applications is still finding apps finishes finding them first, instead of sizing a partial list and showing it as complete
- [fixed] The Applications status card no longer says "Click to Analyze" on a card that can't be clicked; it says sizes are not measured yet
- [fixed] Home and Applications count installed apps the same way (app bundles in /Applications and ~/Applications), and the Applications cards are labelled by folder instead of "System Apps" and "User Apps"
- [fixed] Choosing another folder in Duplicates after a scan clears the old results instead of showing them under the new folder's name
- [fixed] VoiceOver reads whether each Duplicates file-type filter is on
- [fixed] A search with no matches in Orphaned Files, Duplicates or a Disk Cleaner category list says "No matches for" the search and offers a button to clear it, instead of leaving a blank area
- [fixed] Space Lens rows use the same folder icon for Show in Finder as the other pages, instead of an info icon
- [fixed] System Health no longer passes "System Updates" on any macOS 14 or later without checking anything: the row now shows the installed macOS version for reference and does not count toward the score. A `diskutil` failure reads "Couldn't read disk health" instead of "Disk appears healthy", and when a check couldn't run the summary says the result is incomplete instead of "Your Mac is healthy!"
- [fixed] System Health names the startup disk by its real volume name instead of always "Macintosh HD"
- [fixed] Settings > Permissions shows whether Full Disk Access is actually granted, as text and an icon, and checks again when you come back to the app; before, it always showed a green check
- [fixed] The Full Disk Access prompt and Settings list only what the app reads with that access (Smart Scan folders, protected cache and log folders, Safari data, app containers, Space Lens); they no longer promise Mail attachments or system caches
- [fixed] Grant on a Desktop, Documents or Downloads row that macOS already refused no longer does nothing: when the folder is still unreadable, the app opens Privacy & Security > Files and Folders and says why
- [fixed] Permissions no longer shows a red "Revoke" on every readable folder: readable rows offer "Manage in System Settings" only for Full Disk Access and Files and Folders, and world-readable folders such as /Library/Caches lose their FDA badge
- [fixed] After you choose Limited Scan, the Full Disk Access prompt no longer comes back before every Smart Scan (including the menu bar Scan) for the rest of the session, and granting access while the prompt is open closes it and starts the scan instead of leaving it up with only Limited Scan to choose
- [fixed] Startup Items no longer shows 0 Total / 0 Enabled / 0 Disabled / 0 Running before any scan, and Running now counts the same user items as Total instead of adding system items, so it can no longer exceed Total
- [fixed] Port Management says "Couldn't Read Connections" when `lsof` fails instead of "No Connections Found", and the header shows when the list was read
- [fixed] A Mac with no matching TCP connections shows "No Connections Found" in Port Management instead of "Couldn't Read Connections": `lsof` exits 1 when it finds nothing, and that empty result is no longer read as a failure. The open-file check still treats any `lsof` failure as unavailable
- [fixed] When a review plan reaches its 15-minute limit, the review sheet says it expired, even while open, and offers Refresh in place of Approve plan; the sheet offers Refresh whenever the plan on screen cannot be approved
- [fixed] Stop Moving to Trash also appears in the Experience toolbar while items move, so closing the review sheet no longer hides it
- [fixed] The Experience permission help explains what the gap means and has Open System Settings, which opens Full Disk Access; before, it had one sentence and Close
- [fixed] Add a model folder… says when a folder can't be read, and ignores a folder that is already listed instead of adding it twice
- [fixed] Experience plan cards and Recovery history have a chevron, lift on hover and show the focus ring, and Add a model folder… is a bordered button, so they no longer look like the static memory card
- [fixed] The incomplete-receipt notice has the Open Receipts button its message asks for, and each receipt row shows how many items it covers
- [fixed] Learn why on the Home and Disk Cleaner Trash notices opens Experience without starting a scan, and its Opportunities section now starts by explaining why files move to the Trash only from there; before, it landed on a dashboard that never mentioned the Trash and began scanning
- [fixed] Quitting while items move to the Trash asks first: Stop and Quit stops before the next item and quits once the run's receipt is written, and Keep Moving cancels the quit; before, Quit ended the run without a complete receipt
- [fixed] A Disk Cleaner rescan that you cancel, that stops when you leave the page, or that fails no longer shows "Nothing Found": the last finished results stay on screen
- [fixed] Leaving Home, Orphaned Files or Duplicates during a rescan, or cancelling it, keeps the last finished results instead of clearing them
- [fixed] A failed Disk Cleaner or Space Lens scan says why, as Home already did; before, the error was stored but never shown
- [fixed] Browser Privacy names any browser whose data macOS would not let it read (Safari's needs Full Disk Access) and links to Permissions; an empty list no longer shows a green "No Browser Data Found" check when a browser could not be read
- [fixed] Browser Privacy results and the selected Disk Cleaner tab no longer reset each time you switch sections, and a Browser Privacy rescan stopped by leaving keeps the last results
- [fixed] Show in Finder on Home scan rows and Orphaned Files rows no longer appears only on hover: it is always shown, has a name and a focus ring, so the keyboard and VoiceOver can reach it
- [fixed] Stat and info cards on Home, Applications, Startup Items and System Health no longer lift on hover, since they cannot be clicked
- [fixed] Without Full Disk Access, Disk Cleaner now says before its first scan that it reads Desktop, Documents and Downloads and that macOS may ask for access, as Home already did
- [fixed] With two windows open, Home's quick actions and links switch the window you used, not whichever window last showed Home
- [fixed] Memory Guide opens Performance at its read-only guidance instead of the top of the page
- [fixed] Large Files opens Space Lens with the size filter set to items over 100 MB, and the start screen says so before you scan
- [fixed] Space Lens ends with Open in Experience after a scan, like the other read-only lists, and its sidebar section and Disk Cleaner tab show the same content

## [0.1.3] - 2026-01-31

- [fixed] Improve array mutation safety to prevent potential crashes when using Select/Deselect All
- [fixed] Unsafe ForEach pattern in ScanResultsCard that could cause index out of bounds
- [fixed] Force unwrap in FileScanner that could crash if categories array was empty
- [fixed] CGGradient force unwraps in SpaceLensView with fallback rendering
- [fixed] Unsafe direct array index access in PerformanceView

## [0.1.2] - 2026-01-25

- [fixed] Hide toolbar background to prevent visible bar in DetailContentView

## [0.1.1] - 2025-01-24

- [added] `pageTopPadding` theme constant for consistent page layouts
- [changed] All feature views now use dedicated top padding (32pt) for better visual consistency
- [fixed] Permissions page now uses consistent header styling (fonts, spacing) matching other views
- [fixed] Permissions refresh button now uses GlassActionButton component like other pages
- [fixed] NavigationSectionTests updated to include all 10 navigation sections
- [fixed] Flaky testSidebarNavigation UI test now checks for correct elements

## [0.1.0] - 2025-01-20

- Initial release
