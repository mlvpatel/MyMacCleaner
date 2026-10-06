# Applications

Applications is an offline, read-only inventory of installed apps and Homebrew casks.

## What it shows

The page lists discovered applications with local metadata such as name, path, size when available, bundle identifier, version, source, and last-used evidence. It can also detect whether Homebrew is installed and list casks from the local caskroom.

## How to use it

1. Open **Applications** and wait for the local inventory to finish.
2. Search or sort the list to find large or unfamiliar apps.
3. Use **Reveal in Finder** when you want to inspect an app or cask source.
4. Treat missing size, version, or source values as unavailable evidence, not as a recommendation.

## Phase-0 limitation

This feature inventories and reveals local evidence only. It does not uninstall apps, change Homebrew, download updates, remove leftovers, or alter application files.
