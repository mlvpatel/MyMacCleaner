# Permissions Guide

The Permissions page helps you review which local locations MyMacCleaner can currently read.

## What the page checks

The page groups local paths into Full Disk Access, user folders, system folders, application data, and startup paths. For each existing path, it shows whether a local read check succeeded, was denied, or could not be determined. It also records when the page was last checked.

Some user folders are checked only when you visit or refresh this page so the app does not trigger privacy prompts at launch.

## Review access

1. Open **Permissions** in the sidebar.
2. Expand a category to inspect individual paths and their status.
3. Choose **Refresh** after changing access in macOS.
4. Use the supplied System Settings link when macOS requires a manual change.

Full Disk Access and privacy permissions are controlled by macOS. MyMacCleaner can open the relevant System Settings pane, but it cannot grant or revoke access for you.

## Privacy

Permission checks run locally. They assess whether a configured location can be read; the Phase-0 page does not change files, settings, processes, or system configuration.

## Phase-0 limitation

The page is an access-status and settings-navigation aid. It does not perform administrator-authenticated actions.
