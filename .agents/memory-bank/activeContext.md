# Active Context

## Current Focus
The current branch is `codex/realm-convergence`. Keep this file focused on the active branch and the few recent projects a future agent needs by default. Full historical records live under `.agents/memory-bank/history/`.

## Current Branch Projects
These records stay active until the branch is ready to merge. Before merge, move completed project records into the matching history file and leave only the next focus, constraints, and history index here.

- **CalibreActivityLogger Realm Boundary Shrink (2026-07-03, complete):** Removed direct `RealmSwift`, `Realm.Configuration`, and `CalibreActivityLogEntry` usage from `Network/CalibreActivityLogger.swift`. Added pure activity-log write values in `Models/Domain/ActivityLogWriteEvent.swift`; moved Realm object population/update matching into `Models/Realm/CalibreActivityLogRealmMappers.swift`; extended `ActivityLogRepositoryProtocol` / `RealmActivityLogRepository` as the read/write/delete/cleanup boundary for activity logs. `CalibreActivityLogger` now only batches request snapshots and delegates persistence to the repository. `AppContainer` and `DatabaseBootstrapper` construct the logger from `activityLogRepository`, and the now-unused `DatabaseService.loggerConfiguration()` helper was removed. While validating, fixed `RealmActivityLogRepository` to refresh before fetches and key its thread-local Realm cache by configuration to avoid stale in-memory Realm reuse across async tests. Also corrected `UnifiedSearchIntegrationTests` to build its test `CalibreServerService` with `container.databaseService` rather than `DatabaseService.shared`. Validation: logger Realm scans passed with no matches; focused `CalibreActivityLoggerTests`, `ActivityLogRepositoryTests`, `ActivityListViewModelTests`, `DatabaseBootstrapperTests`, `UnifiedSearchServiceTests`, and `UnifiedSearchIntegrationTests` passed (24 tests); standard iOS Simulator build passed; `git diff --check` passed.
- **Book Detail Readium Nil Book Regression Fix (2026-07-03, complete):** Fixed a state mismatch where opening a book from Book Detail populated `ReadingSessionManager.readerInfo` but left `readingBook` nil or stale, which could surface as "Nil Book" when opening Readium EPUB or related reader sheets. `BookDetailViewModel` now routes read and preview-dismiss entry points through a shared helper that sets the active reading book via `CalibreBookManager`, allowing `ReadingSessionManager` to derive matching `readerInfo`. Added regression coverage to `BookDetailViewModelTests.testReadBookWhenInShelf` asserting the active reading book matches the selected detail book. Validation: focused `BookDetailViewModelTests`, `YabrReadiumReaderViewControllerTests`, `ReadiumPreferenceValueTests`, and `ReaderPreferenceRepositoryTests` passed (45 tests); `git diff --check` passed; standard iOS Simulator build passed.
- **Readium Preference Realm Boundary Shrink (2026-07-03, complete):** Split `ReadiumPreferenceValue` out of `Views/ReadiumView/ReadiumPreferenceAdapter.swift` into `Models/Domain/ReadiumPreferenceValue.swift`, leaving the adapter responsible only for Readium/UI preference conversion. Moved `ReadiumPreferenceRealm` value mapping into `Models/Realm/ReadiumPreferenceRealmMappers.swift`, so `ReadiumView` no longer directly imports `RealmSwift` or references `ReadiumPreferenceRealm`. Repository APIs and Realm schema are unchanged. Validation: ReadiumView RealmSwift scan and adapter `ReadiumPreferenceRealm` scan passed with no matches; focused `ReadiumPreferenceValueTests`, `ReaderPreferenceRepositoryTests`, `YabrReadiumReaderViewControllerTests`, and `YabrReaderSettingsViewModelTests` passed (24 tests); standard iOS Simulator build passed.

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
