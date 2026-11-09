# Duplicate Finder

Duplicate Finder is an offline review view for exact duplicate-file evidence.

## What it shows

The scanner groups files that have matching content evidence. Each group is shown for review so you can understand where duplicate-looking files exist and how much apparent space they represent.

The app keeps this evidence local. Groups have no checkboxes, keeper or selection controls; **Open in Experience** at the end of the list leads to the only screen that can move files.

## How to use it

1. Open **Duplicates** and scan a permitted location. Choosing another folder after a scan clears the old results, so one folder's groups never appear under another folder's name.
2. Inspect each group before making decisions outside the app.
3. Use filtering and reveal actions to understand the source paths. The file-type cards are filters, and VoiceOver reads whether each one is on. A search or filter that matches nothing says so and offers **Clear Filters**.
4. Keep original project, photo, media, and backup context in mind when interpreting a duplicate group.

## What this page does not do

This feature finds and explains duplicate evidence only. It does not remove files, move items to Trash, choose a keeper, or change filesystem content.

A scan can be cancelled at any point, including while a large file is being hashed. Leaving the page while a scan runs stops it; when you come back the page says the last scan stopped and still shows the results of the last finished scan. It compares at most 500,000 files; the header says when results were cut short. Hard links to the same file are counted once, and a file that cannot be read to the end is left out rather than matched on a partial read.
