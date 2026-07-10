# Active Context

## Current Focus

No active branch-specific workstream is currently recorded.

## Current Branch Notes

- 2026-07-10: `codex/restore-google-admob-integration` is restoring shelf
  AdMob placement. Current unmerged work uses `ShelfAdLayoutPolicy` to insert
  ads at roughly one per effective viewport, never denser than one per screen.
  Recent uses regular-width native end-caps occupying the last three shelf
  columns in a normal 200pt book row when there are enough books to keep the
  row content-led; compact width, narrow split view, or missing native inventory
  falls back to inline adaptive banners. Discover keeps ads between sections:
  regular width uses a 200pt horizontal native strip, while compact/missing
  native falls back to an adaptive banner row. The old wide iPad side rail is no
  longer part of the shelf layout.
  Review follow-up now keeps native cache state in per-shelf `ShelfNativeAdStore`
  instances with an 8-entry LRU, 55-minute loaded TTL, and 60-second failure
  cooldown. Native callbacks verify the current `AdLoader`; native strip content
  uses container width minus 56pt for the 28pt side gutters; native failures use
  an inline adaptive banner capped at 60pt. Recent and Discover use real bottom
  `safeAreaInset` exclusion and no longer retain poster/sidebar layout branches.
  Focused shelf tests now cover store isolation, expiry, retry cooldown, and LRU
  eviction. `Info.plist` already contains app id
  `ca-app-pub-2603711004804215~7977491314`; `YabrInfo.plist` now stores native
  shelf unit `ca-app-pub-2603711004804215/1060349074` and keeps DEBUG on the
  Google test native unit. Latest validation passed `git diff --check`,
  `ShelfAdLayoutPolicyTests` (11 tests), and iOS Simulator build using Xcode's
  default package cache. The standard `/tmp/YabrSourcePackages` cache path was
  incomplete during an earlier run and failed package resolution before
  compilation.
- PR #88 (`codex/folio-reader-integration`) has been merged. Reader workspace,
  FolioReader integration, reader tab hot-mounting, and persistent active reader
  restore are archived in [Reader Modernization](history/reader-modernization.md).
- The manual sync metadata refresh cleanup from the same merged branch is
  archived in [Network, Search, And Cache Modernization](history/network-search-cache-modernization.md).
- Keep this file as a short handoff entrypoint. Add only current, unresolved, or
  high-risk context here; move completed project records into the matching
  history file before merge.
- If a task changes architecture, validation status, known risks, or handoff
  expectations, update this file or the relevant history file before finishing.

## History Index

- [Reader Modernization](history/reader-modernization.md): Readium,
  FolioReader, PDF reader, reading position, highlights, preferences, Book
  Detail reader work, and reader workspace/window modernization.
- [AppContainer And Concurrency Modernization](history/app-container-concurrency-modernization.md):
  AppContainer demotion, manager async streams, Combine removal, and concurrency
  hardening.
- [Shelf Modernization](history/shelf-modernization.md): Recent/Discover shelf
  UI, `YabrShelfDataModel`, shelf bootstrap, and shelf Swift Concurrency
  migration.
- [Realm Boundary Convergence](history/realm-boundary-convergence.md): Realm
  boundary shrinkage, repository ownership, mapper extraction, and persistence
  cleanup.
- [Network, Search, And Cache Modernization](history/network-search-cache-modernization.md):
  Calibre networking, unified search/category, cache behavior, downloads, and
  network tests.
- [ModelData Elimination](history/modeldata-elimination.md): ModelData
  reduction, AppContainer introduction, protocol migration, and final deletion.
- [Legacy Completed Tasks And Milestones](history/legacy-completed-milestones.md):
  Older completed checklists and cross-cutting historical context.

## Active Constraints

- Preserve user changes; do not revert unrelated dirty work.
- Do not introduce CocoaPods, Carthage, or workspace-level dependency changes.
  The project uses Swift Package Manager.
- Prefer repositories/services/managers over direct Realm or network work in
  SwiftUI views.
- Before any `xcodebuild test`, run:

```bash
xcrun simctl shutdown all
```

- Standard iOS Simulator build:

```bash
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
```
