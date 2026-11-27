# Permissions Guide

The Permissions page helps you review which local locations MyMacCleaner can currently read.

## What the page checks

The page groups local paths into Full Disk Access, user folders, system folders, application data, and startup paths. For each existing path, it shows whether a local read check succeeded, was denied, or could not be determined. It also records when the page was last checked.

Folders are checked only when you visit or refresh this page, so the app does not probe folders or trigger privacy prompts at launch. The checks run off the main thread, so the window stays responsive while macOS shows a folder prompt.

## Review access

1. Open **Permissions** in the sidebar.
2. Expand a category to inspect individual paths and their status.
3. Choose **Refresh** after changing access in macOS.
4. Use the supplied System Settings link when macOS requires a manual change. Readable rows offer **Manage in System Settings** only where System Settings controls access (Full Disk Access, and Desktop, Documents or Downloads); world-readable folders have no button.
5. macOS asks about Desktop, Documents or Downloads only once. If **Grant** still can't read the folder, the app opens **Privacy & Security > Files and Folders** in System Settings and says so.

Full Disk Access and privacy permissions are controlled by macOS. MyMacCleaner can open the relevant System Settings pane, but it cannot grant or revoke access for you.

## What Full Disk Access changes

Full Disk Access is optional. With it, Smart Scan reads Desktop, Documents and Downloads without a macOS prompt for each, and can read cache and log folders that macOS protects. Browser Privacy can read Safari history and website data, Orphaned Files can look inside protected app containers, and Space Lens can size protected folders. **Settings > Permissions** shows whether access is granted and checks again when you come back to the app.

## Privacy

Permission checks run locally. They assess whether a configured location can be read; the page does not change files, settings, processes, or system configuration.

## What this page does not do

The page is an access-status and settings-navigation aid. It does not perform administrator-authenticated actions.
