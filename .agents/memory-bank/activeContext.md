# Active Context

## Current Focus
The current branch is `fix/library-book-list`. Branch implementation work has been completed and archived before PR creation.

Keep this file focused on the active branch and the few current project notes a future agent needs by default. Full historical records live under `.agents/memory-bank/history/`.

## Current Branch Projects
Uncommitted reader preference compatibility work is present in the working tree:
`ReaderEnginePreferences.themeMode` now uses canonical shared theme values, and
`ReaderPreferenceRepository.loadInitialPreferences` falls back across compatible
reader engines when the target engine has no saved preferences for the book.
FolioReader now also has full native per-book preference persistence so
Folio-only settings are not lost through the cross-engine compatibility layer.

Reader presentation is being moved off the old single global reader state. The
current working tree adds `ReaderPresentation` snapshots to
`ReadingSessionManager`, routes shelf/detail/import/reading-position open actions
through `openReader(...)`, removes the `AppContainer.presentingStack` dismiss
workaround, and binds FolioReader providers to the concrete reader instance's
book/readerInfo instead of `bookManager.readingBook` / `sessionManager.readerInfo`.
Validation completed for this slice:

```bash
git diff --check
xcrun simctl shutdown all
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages -only-testing:YetAnotherEBookReaderTests/ReadingSessionManagerTests -only-testing:YetAnotherEBookReaderTests/MainViewModelTests -only-testing:YetAnotherEBookReaderTests/BookDetailViewModelTests -only-testing:YetAnotherEBookReaderTests/RecentShelfViewModelTests -only-testing:YetAnotherEBookReaderTests/FolioReaderProviderBookIdTests
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
```

Recorded result: `git diff --check` passed, 71 focused tests passed, and the
iOS Simulator build succeeded. Follow-up risk: the compatibility
`readingBook`/`readerInfo`/`presentingEBookReaderFromShelf` accessors still exist
inside the manager layer for older tests/callers and can be removed in a later
cleanup once remaining manager-level references are migrated.

Review follow-up completed: `ReaderWorkspaceView` now keys `YabrEBookReader` by
`ReaderPresentation.id` so activating another reader presentation rebuilds the
underlying UIKit reader instead of reusing the old representable controller.
Validation rerun after the fix: `git diff --check`, the same 71 focused reader
tests, and the standard iOS Simulator build all passed.

Completed `fix/library-book-list` work was archived into [Network, Search, And Cache Modernization](history/network-search-cache-modernization.md) under **fix/library-book-list Branch Archive (2026-07-05, complete)**.

## Pre-Merge Archive Rule
- Before merging a branch, archive completed branch work from `Current Branch Projects` into the matching `.agents/memory-bank/history/` project file.
- Keep `activeContext.md` as a short entrypoint: current focus, active branch projects, constraints, and links to history.
- Prefer project boundaries over dates or arbitrary entry counts when moving records.

## History Index
- [Realm Boundary Convergence](history/realm-boundary-convergence.md): Realm boundary shrinkage, repository ownership, mapper extraction, and persistence cleanup.
- [AppContainer And Concurrency Modernization](history/app-container-concurrency-modernization.md): AppContainer demotion, manager async streams, Combine removal, and concurrency hardening.
- [Shelf Modernization](history/shelf-modernization.md): Recent/Discover shelf UI, YabrShelfDataModel, shelf bootstrap, and shelf Swift Concurrency migration.
- [ModelData Elimination](history/modeldata-elimination.md): ModelData reduction, AppContainer introduction, protocol migration, and final deletion.
- [Reader Modernization](history/reader-modernization.md): Readium, FolioReader, PDF reader, reading position, highlights, preferences, and Book Detail reader work.
- [Network, Search, And Cache Modernization](history/network-search-cache-modernization.md): Calibre networking, unified search/category, cache behavior, downloads, and network tests.
- [Legacy Completed Tasks And Milestones](history/legacy-completed-milestones.md): Old completed checklists and cross-cutting historical context.

## Active Constraints
- **Do NOT** introduce CocoaPods or modify workspace files; the project relies entirely on Swift Package Manager.
- **Decoupling Goal:** Views should minimize direct dependency on `ModelData` for network operations; logic should reside in dedicated ViewModels.
- **Validation Workflow:** Before any `xcodebuild test`, shut down running simulators with `xcrun simctl shutdown all`. Add `-clonedSourcePackagesDirPath /tmp/YabrSourcePackages` to `xcodebuild` build/test commands to reuse SPM checkouts. After validation passes, start one Debug run through the Xcode MCP integration when that tool is available.
