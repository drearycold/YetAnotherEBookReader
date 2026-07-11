# Active Context

## Current Focus

No active branch-specific workstream is currently recorded.

## Current Branch Notes

- No active branch-specific workstream is currently recorded.
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

## Latest UI Test Verification (2026-07-11)

- Expanded `YetAnotherEBookReaderUITests` to cover launch/tab navigation,
  Recent mock-book details, Browse reopen behavior, and Settings mock-server
  visibility.
- The `--ui-testing-mock-library` path now skips local Documents-library
  scanning, synchronously seeds/persists the fixed mock book, and publishes the
  shelf update so UI tests do not depend on simulator user data.
- Verified with iPhone 17 Simulator using isolated `/tmp` DerivedData and SPM
  cache: `build-for-testing` passed and
  `-only-testing:YetAnotherEBookReaderUITests` passed all 4 tests.

## Browse UI Test Expansion (2026-07-11)

- Expanded the isolated mock library to three persisted Realm books with
  distinct title/author/tag/series metadata, fixed modification dates, and
  EPUB sizes. Only `Mock Book Title` is in Recent; Alpha and Beta are
  Browse-only.
- Added stable Browse accessibility identifiers for search, sorting, batch
  selection, book rows, and the format confirmation popover. Added search,
  title sort, and batch selection/confirmation UI coverage, plus fixture
  assertions in `LibraryInfoBookListViewModelTests`.
- `build-for-testing` passed. Two final complete UI suite runs on iPhone 17
  passed 7/7 each with isolated `/tmp/YabrPhase2DerivedData` and
  `/tmp/YabrPhase2SourcePackages`. Runtime was about 236s and 292s; the
  requested 90-second target remains unmet because each UI test launches a
  fresh app and simulator/XCTest startup dominates the run.

## Browse Category UI Test Expansion (2026-07-11)

- Extended the offline UI-test fixture with three persisted category caches:
  Authors, Tags, and Series. Each contains Mock, Alpha, and Beta entries with
  count, URL, and generation values derived from the three fixed mock books;
  initialization writes these caches directly and does not invoke category
  refresh or network sync.
- Added stable normalized accessibility identifiers for category entry points,
  category pages/search/clear controls/items, header category menus and Done,
  and filter chips/removal/clear controls.
- Added root Authors filtering, Series category search/clear, and header Tags
  multi-select/remove/clear UI coverage. Added fixture assertions for category
  metadata and cache generation.
- `build-for-testing` passed. Focused Browse/category unit tests passed 53/53.
  Two post-fix complete UI suite runs on iPhone 17 passed 10/10 each using
  `/tmp/YabrPhase3DerivedData` and `/tmp/YabrPhase3SourcePackages`; runtimes
  were about 283s and 279s. The suite contains no fixed sleep.
