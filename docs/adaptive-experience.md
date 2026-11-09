# Adaptive Experience

Adaptive Experience (**Experience** in the sidebar) is the only place where MyMacCleaner changes a file. It shows local storage evidence, builds a review plan, and after you approve that plan it moves the planned files to the Trash and writes a receipt. Home and Disk Cleaner lists end with **Open in Experience**, which brings you here. **Learn why** on the Home and Disk Cleaner Trash notices also brings you here, without starting a scan: the **Opportunities** section opens by saying why files move to the Trash only from this page, and shows the plan already loaded, if any.

## Three depths

The **Detail** picker in the toolbar shows the same evidence at three depths:

- **Guided** says in plain words what this Mac can review, whether the scan finished, and that approved items go to the Trash first so you can restore them.
- **Standard** adds that eligibility comes from a fixed policy and that approved cleanup is always Trash-first.
- **Technical** adds that the plan is digest-bound and that receipts use opaque identifiers, and the review sheet shows each item's opaque identity.

The depth changes only how much is explained. It never changes what is eligible or what a plan contains.

## What is eligible

One rule decides eligibility: a regular file inside `~/Library/Caches/com.apple.iconservices.store` that has not been modified for at least 15 minutes and that no running process holds open. Everything else the scan finds stays out of the plan and is only counted ("Found for review only, not in the plan"). Recent macOS versions rarely create that folder, so on many Macs the plan is empty and the page says **No eligible cleanup opportunities yet.**

Developer tools, editor data, Docker, package managers, and AI model stores (Hugging Face, Ollama, and any model folder you add with **Add a model folder…**) appear under **Protected workflow data** as inventory only. They can never enter a plan. Adding a folder that is already listed, or one the app cannot read, adds nothing and says why. Permission gaps and items on external volumes are shown as warnings and cannot be selected either. Select a permission gap under **Coverage** for help: **Open System Settings** opens Full Disk Access, and a Refresh afterwards includes the folders it unlocked.

## Review, approve, move to Trash

1. Open **Experience**. The page loads evidence the first time it opens, once you close the welcome sheet, and loads it again on a later visit only if it is more than five minutes old or another page has scanned since; otherwise it shows the same evidence. Leaving the page stops a load, but never a move to the Trash. Choose **Refresh** (Command-R) to scan again now or **Stop scan** (Command-.) to stop a refresh.
2. Read **Opportunities**. Each planned item shows its name, parent folder, conservative size, and recovery path. The page lists the first 50 items and counts the rest.
3. Select an item to open **Review evidence**. It says whether the current plan is valid for review and lists the planned items.
4. Choose **Approve plan**. A confirmation names up to 10 items and the total, for example "Move 3 items (12.4 MB) to the Trash?". Choose **Move to Trash** to start, or dismiss the dialog to leave everything in place.
5. While items move, **Stop Moving to Trash** stops before the next item. It is in the review sheet and, after you close the sheet, in the toolbar in place of Refresh (Command-. in both). Items already moved stay in the Trash and are listed in the receipt. Refresh is unavailable during the move. Quitting during the move (Command-Q, Quit in the menu bar, or logging out) asks first: **Stop and Quit** stops the same way and quits once the run has ended and its receipt is written; **Keep Moving** cancels the quit.
6. When the run ends, the page shows a count such as "Moved 12, skipped 2, failed 0." and a **View receipt** button. VoiceOver announces the start and the result.

Approval covers only the plan you reviewed. A plan expires 15 minutes after it is built; when it does, the review sheet says so, even if it was already open, and offers **Refresh** in place of **Approve plan**. The sheet offers Refresh whenever the plan on screen cannot be approved. If the evidence or the plan changes before you confirm, nothing moves and the page asks you to review the updated plan.

Items move one at a time. Just before each move the app checks the item again: it must be the same file, still pass the eligibility rule on a fresh scan of its folder made for this run (never the scan shared with Home and Disk Cleaner; the open-file check included), sit inside the named cache folder, and have exactly one hard link. An item that fails any check is skipped and stays where it is.

## Receipts and recovery

Before the first item moves, the app writes a local receipt of what it intends to do, then records each item's outcome. If the receipt history cannot be opened, the run does not start.

**Recovery history** opens **Recovery receipts**, newest first. Each receipt shows its date, a status (for example Complete, Partly complete, Interrupted, or Needs attention), how many items it covers, and a recovery note such as "Trash recovery may still be available." Receipts use opaque identifiers and do not show local paths. They are stored only on this Mac, in `~/Library/Application Support/MyMacCleaner/Receipts`, and kept for up to 90 days or 500 finished receipts.

Until you empty the Trash, you can restore a moved item from the Trash in Finder. See [RECOVERY.md](RECOVERY.md) for how interrupted runs are reconciled.

## What this page does not do

Adaptive Experience does not empty the Trash, delete files permanently, restore files for you, ask for an administrator password, or move anything outside the one named cache folder. The full rules are in [SAFETY-CONTRACT.md](SAFETY-CONTRACT.md).
