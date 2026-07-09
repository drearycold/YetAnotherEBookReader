# Active Context

## Current Focus

Current branch: `codex/folio-reader-integration`.

Current search cleanup: Library book list manual sync now rebuilds the current
search page and forces metadata refresh for loaded books, so refreshed
`format_metadata` updates `CalibreBook.formats`. After a manual sync, subsequent
load-more operations keep forcing metadata refresh for newly loaded books without
rebuilding the first page again.

Latest local commit at cleanup time:

```text
26d65322 polish welcome empty shelf onboarding
```

## Current Branch Notes

- Recent reader workspace and FolioReader integration work is archived in
  [Reader Modernization](history/reader-modernization.md) under
  **Reader Workspace / FolioReader Integration Branch Archive (2026-07-09, complete)**.
- Keep this file as a short handoff entrypoint. Add only current, unresolved, or
  high-risk context here; move completed project records into the matching
  history file before merge.
- If a task changes architecture, validation status, known risks, or handoff
  expectations, update this file or the relevant history file before finishing.
- Latest validation for manual sync metadata refresh (2026-07-09):
  `git diff --check`, focused `UnifiedSearchServiceTests`,
  `UnifiedSearchIntegrationTests`, `V2MigrationDependencyTests`, and standard
  iOS Simulator build all passed.

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
