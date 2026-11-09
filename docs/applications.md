# Applications

Applications is an offline, read-only inventory of installed apps and Homebrew casks.

## What it shows

The page lists discovered applications with local metadata such as name, path, size when available, bundle identifier, version, source, and last-used evidence. It can also detect whether Homebrew is installed and list casks from the local caskroom.

An installed app is an app bundle directly inside /Applications or ~/Applications. Before sizes are measured, the cards count the apps found in each of those folders; Home's app count uses the same two folders, so the two pages agree.

## How to use it

1. Open **Applications** and wait for the local inventory to finish. Leaving the page stops discovery and size analysis; they start again on your next visit. If you choose **Analyze Apps** while apps are still being found, the page finishes finding them first, so every app gets a size.
2. Search or sort the list to find large or unfamiliar apps.
3. Use **Reveal in Finder** when you want to inspect an app or cask source.
4. Treat missing size, version, or source values as unavailable evidence, not as a recommendation.

## What this page does not do

This feature inventories and reveals local evidence only. It does not uninstall apps, change Homebrew, download updates, remove leftovers, or alter application files.
