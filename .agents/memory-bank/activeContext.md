# Active Context

## Current Focus
The current branch is `fix/library-book-list`. This is a fresh project context after archiving the completed Realm boundary convergence handoff records on 2026-07-04.

Keep this file focused on the active branch and the few current project notes a future agent needs by default. Full historical records live under `.agents/memory-bank/history/`.

## Current Branch Projects
Use this section for the new project. Archive completed entries into the matching history file before merge.

- **Library Book List Refresh Pagination Fix (2026-07-04, complete):** Fixed a browse/search list cache bug where server-side book additions could update `totalNumber` while leaving newly inserted sorted entries invisible and duplicating old tail entries. `LibrarySearchService.searchAndFetchMetadata` now rebuilds from `offset=0` for force refreshes, missing/stale cache sources, and detected unstable incremental pages (`total_num` change or overlapping returned IDs). Per-library source `bookIds` are deduplicated while preserving order before metadata resolution and cache save. Added `UnifiedSearchServiceTests` regressions for force refresh offset reset and overlap-triggered rebuild after server insert.
- **Library Search Server Mutation Coverage (2026-07-04, complete):** Expanded `UnifiedSearchServiceTests` service-layer coverage for server-side delete (`total_num` drops), same-total reorder/metadata mutation (overlap-triggered rebuild), stale-generation metadata refresh, and duplicate server ID de-duplication. Validation: full `UnifiedSearchServiceTests` passed (15 tests); `UnifiedSearchIntegrationTests` + `UnifiedSearchMergeServiceTests` passed (14 tests); `git diff --check` passed.

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
