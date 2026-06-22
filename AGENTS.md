---
trigger: always_on
description: Project workflow rules, architecture map, and current handoff context
---

# AGENTS.md

This file is the working guide for agents contributing to YetAnotherEBookReader
(publicly D.S.Reader). Follow it before editing code.

## First Steps

- Read `.agents/memory-bank/activeContext.md` before starting any task.
- Read any task-relevant memory-bank notes:
  - `.agents/memory-bank/refactoring-context.md` for architecture/refactoring work.
  - `.agents/memory-bank/productContext.md` for product and platform context.
  - `.agents/memory-bank/unified-search-analysis.md` and
    `.agents/memory-bank/unified_search_analysis.md` for search/cache work.
- After completing a task, update the relevant memory-bank file when the task
  changes project direction, architecture, known risks, test status, or handoff
  context.
- Preserve user changes. The worktree may be dirty; do not revert unrelated
  edits.

## Project Snapshot

- App: iOS 15+ and macOS 12+ via Catalyst ebook reader.
- UI: SwiftUI for app structure/settings and UIKit for reader-heavy surfaces.
- Readers: Readium R2 for EPUB/PDF/CBZ, FolioReaderKit for legacy EPUB, custom
  PDFKit stack for YabrPDF.
- Persistence: RealmSwift for metadata, shelves, annotations, reading positions,
  preferences, search/category cache, and activity logs.
- Networking: Calibre content server APIs through `CalibreServerService`,
  Kingfisher for authenticated images, GCDWebServer/Readium web server pieces for
  local reader assets.
- Dependencies: Swift Package Manager only. Do not add CocoaPods, Carthage, or a
  separate workspace.

## Build And Test

Use the shared Xcode project and scheme:

```bash
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
```

For runtime behavior, repository logic, search, reader changes, or any non-trivial
Swift change, prefer tests:

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData
```

Mac Catalyst build command:

```bash
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader-Catalyst -destination 'platform=macOS,variant=Mac Catalyst' build
```

If a full test run is too expensive for the change, run the narrowest relevant
test target or class first, then state exactly what was and was not verified.

## Architecture Map

### Entry And App State

- `YetAnotherEBookReader/YetAnotherEBookReaderApp.swift` creates the global
  `ModelData`, initializes Realm on scene activation, and injects shared
  environment objects.
- `YetAnotherEBookReader/MainView.swift` owns the main tab shell:
  - `RecentShelfView`
  - `SectionShelfView`
  - `LibraryInfoView`
  - `SettingsView`
- `YetAnotherEBookReader/Models/ModelData.swift` is still the composition root
  and compatibility facade. It wires managers, repositories, services, download
  handling, reading sessions, fonts, and app-wide Combine subjects.

### Managers

Use managers for app-domain coordination. Avoid moving new business logic back
into `ModelData` unless the change is a compatibility shim.

- `CalibreServerManager`: server list, credentials, reachability probes,
  DSReader Helper configuration.
- `CalibreLibraryManager`: library list, local library bootstrapping, library
  sync state, category/library probing.
- `CalibreBookManager`: shelf state, book CRUD coordination, cache state,
  Goodreads shelf hooks.
- `ReadingSessionManager`: selected reading book, reader/format preference,
  reading position selection, reader-close progress handling.
- `FontsManager`: custom font import, reload, removal.
- `BookDownloadManager`: active downloads, downloaded format state.

### Repository Layer

Repository protocols isolate Realm access from managers, services, and views.
Prefer extending repositories over adding direct Realm calls in UI or manager
code.

- `Models/Repositories/ServerRepository.swift`
- `Models/Repositories/LibraryRepository.swift`
- `Models/Repositories/BookRepository.swift`
- `Models/Repositories/ReadingPositionRepository.swift`
- `Models/Repositories/AnnotationRepository.swift`
- `Models/Repositories/RealmSearchCacheStore.swift`
- `Models/Protocols/SearchCacheRepository.swift`
- `Models/Protocols/CategoryCacheRepository.swift`

### Models

- `CalibreData.swift` has been split (Milestone P2/A11) into focused files in
  `Models/` and `Network/`. The decomposition is a zero-behavior move:
  - `CalibreCoreModels.swift`: `CalibreServer`, `CalibreLibrary`,
    `CalibreBook`, `CalibreSyncStatus`.
  - `ReadingPositionModels.swift`: `BookDeviceReadingPosition`,
    `BookDeviceReadingPositionHistory`, reading statistics.
  - `CalibreHighlightStyle.swift`: `BookHighlightStyle` (only model file in the
    split that imports UIKit).
  - `CalibreTasks.swift`: network/metadata task structs
    (`CalibreBookTask`, `CalibreBooksMetadataRequest`, `CalibreBooksTask`,
    `CalibreLibraryProbeTask`, `CalibreLibrarySearchTask`,
    `CalibreBookSetLastReadPositionTask`, `CalibreBookUpdateAnnotationsTask`).
  - `CalibrePayloadModels.swift`: Codable API entry/result payloads
    (`CalibreBookEntry`, `CalibreBookLastReadPositionEntry`,
    `CalibreBookAnnotationsResult`, `CalibreBookAnnotationsMap`,
    `CalibreLibraryBooksResult`, etc.).
  - `CalibreSyncModels.swift`: custom columns, category keys, probe/sync
    requests, `CalibreCdbCmdListResult`.
  - `CalibrePluginModels.swift`: DSReader Helper / Count Pages / Goodreads Sync
    preferences and `CalibreDSReaderHelperConfiguration`.
  - `Network/CalibreActivityModels.swift`: `CalibreActivity`/`Start`/`Finish`.
  - `CalibreServerConfigProvider.swift`: the `CalibreServerConfigProvider`
    protocol used to bridge managers/services with the `ModelData` facade.
  - `Array+Chunks.swift`: generic `Array.chunks(size:)` helper.
- `RealmModel.swift`: Realm object schema. Treat edits here as migration work.
- `YabrData.swift`: format, reader, reader-info, and app-specific value types.
- `BookFiles.swift`: import and local-file helpers.
- `BookPreference.swift`, `BookBookmark.swift`, `BookHighlight.swift`: reader
  preferences and annotation value types.

### Search And Category

The modern path is value-type/actor based. Do not revive direct
`CalibreUnifiedSearchObject` bindings in views.

- `ModelData` now owns the V2 root dependencies directly:
  `searchCacheRepository`, `librarySearchService`,
  `unifiedSearchService`, `libraryCategoryService`, and
  `unifiedCategoryService`.
- `LibrarySearchService` performs per-library search, online/offline source
  selection, metadata fetch, and cache writes.
- `UnifiedSearchService` is an actor that coordinates active multi-library
  searches and streams `SearchUpdate`.
- `UnifiedSearchMergeService` merges per-library results in memory.
- `UnifiedCategoryService` and `UnifiedCategoryMergeService` merge category
  cache results.
- `UnifiedSearchViewModel` and `UnifiedCategoryViewModel` are the UI-facing
  adapters for LibraryInfo views.
- `Models/CalibreBrowser/CalibreBrowser.swift` and
  `CalibreLibrarySearchManager` are historical only; treat older analysis that
  references them as pre-P1e context rather than live architecture.

### Reader Stack

- `Views/Reader/YabrEBookReader.swift` chooses the actual reader implementation
  from `ReaderInfo`.
- `Views/Reader/YabrEBookReaderNavigationController.swift` owns reader lifecycle
  hooks and session start/end handling.
- `Views/Reader/ReaderEngineProtocol.swift` is the common bridge for reader
  position, preferences, and highlights.
- `Views/ReadiumView/*` contains Readium EPUB/PDF/CBZ integration.
- `Views/FolioReaderView/*` contains legacy FolioReader EPUB integration.
- `Views/PDFView/*` contains the custom PDFKit reader.

### Main UI Areas

- `Views/LibraryInfoView/*`: browse/search/category views and view models.
- `Views/BookDetailView/*`: book detail, preview, activity, reading position UI.
- `Views/SettingsView/*`: settings, server/library configuration, reader
  options, import pickers.
- `Views/ShelfView/*`: native SwiftUI Recent/Discover shelves (`RecentShelfView`, `SectionShelfView`, view models, and components). The shelf data model (`YabrShelfDataModel`) lives in `Models/ShelfDataManager.swift` (moved out of `Views/ShelfView/` in Milestone P2/A10).
- `Views/DictView/*`: dictionary and external lookup UI.

## Coding Rules

- Keep changes scoped to the feature or bug. Avoid opportunistic rewrites.
- Prefer existing patterns and local helpers over new abstractions.
- New complex SwiftUI views should use dedicated ViewModels instead of putting
  networking, Realm queries, or mutation logic in the view.
- Preserve the `ModelData` facade where existing callers depend on it, but place
  new domain behavior in managers/services/repositories.
- Do not introduce direct `RealmSwift` usage in SwiftUI views unless there is a
  strong compatibility reason. Prefer value types and observable ViewModels.
- Avoid force unwraps and `try!` in new code. Convert failures into optional
  handling, thrown errors, or logged no-op behavior as appropriate.
- Keep Combine and Swift Concurrency boundaries explicit. Avoid mixing queue
  hopping, actor calls, and Realm writes without a clear ownership path.
- Do not add debug `print` noise unless diagnosing a current issue; remove it
  before finishing.
- When adding files, ensure they are registered in the Xcode project target.

## Realm And Threading Rules

- Realm objects are thread-confined. Do not pass live Realm objects across
  threads, queues, actors, or async boundaries.
- Pass `Realm.Configuration`, primary keys, or value types across concurrency
  boundaries.
- Open a Realm on the current thread/queue when needed. The current good pattern
  is: use `databaseService.realm` only on the main thread, otherwise open
  `Realm(configuration: databaseService.realmConf)` on the current thread.
- Do not reuse `databaseService.realm`, `server.realmPerf`, or a cached main
  Realm from a background queue.
- Keep Realm write transactions short. Do expensive sorting, merging, network
  preparation, and value construction outside writes.
- Schema changes require a version bump and migration handling in
  `ModelData.tryInitializeDatabase(statusHandler:)`.

## Common Change Paths

### Server Or Library Settings

Start with `ServerViewModel`, `LibraryViewModel`, `CalibreServerManager`,
`CalibreLibraryManager`, and the server/library repositories. Keep SwiftUI forms
focused on state presentation and user actions.

### Search Or Browse

Start with `LibraryInfoViewModel`, `UnifiedSearchViewModel`,
`UnifiedSearchService`, `LibrarySearchService`, and `RealmSearchCacheStore`.
Preserve criteria isolation, limit expansion, cache generation checks, and the
empty-library-ids meaning of "all active libraries".

### Book Detail

Start with `BookDetailViewModel` and `BookDetailSubviews`. Avoid reintroducing
direct `ModelData` or Realm dependencies into `BookDetailView` subviews.

### Reader Behavior

Start with `ReadingSessionManager`, `ReaderEngineProtocol`,
`YabrEBookReader.swift`, and the specific engine implementation. Any progress,
highlight, or preference change must be checked across YabrPDF, Readium, and
FolioReader paths when the behavior is shared.

### PDF Reader

`YabrPDFViewController` is a coordinator. Keep specialized behavior in the
existing managers/extensions:

- `PDFAnnotationManager`
- `PDFBookmarkManager`
- `PDFSearchController`
- `PDFMarginCropController`
- `YabrPDFViewController+Chrome`
- `YabrPDFViewController+Navigation`
- `YabrPDFViewController+Options`
- `YabrPDFViewController+Selection`
- `YabrPDFViewController+Sharing`

Avoid growing the main controller again.

## Current Handoff Context

The main workstream is still reader architecture modernization and large-file
decomposition.

Recent important state:

- **P2/A21 SwiftUI Native Shelves and UIKit Removal (Milestone A21):** Completed the UIKit-to-SwiftUI native migration of Recent and Discover shelves (Stage A21-S1 through A21-S6). Deleted `RecentShelfController.swift`, `RecentShelfUI.swift`, `SectionShelfController.swift`, and `SectionShelfUI.swift` from the codebase. Removed the `ShelfView` SPM dependency usage entirely and cleaned up related publishers/subjects/computed-properties in `RecentShelfViewModel`, `SectionShelfViewModel`, `ModelData`, `CalibreBookManager`, `ShelfDataManager`, `ShelfDisplayModels`, `MainView`, and associated tests.
- **P2/A22 CalibreSearchCache Deprecated Properties (Milestone A22):** Removed
  4 deprecated `@Persisted` properties (`generation`, `totalNumber`, `bookIds`,
  `books: List<CalibreBookRealm>`) from `CalibreLibrarySearchObject` in
  `CalibreSearchCache.swift`. Bumped Realm schema version 139→140 (updated
  `ModelData.RealmSchemaVersion`, `CFBundleVersion` in both iOS and macOS
  Info.plist files, and added migration block entry for `oldSchemaVersion < 140`).
- **P2/A13 Book.swift Deleted (Milestone A13):** Deleted the entire 378-line
  `Models/Book.swift`. The file was not registered in the Xcode project and
  was never compiled; all 7 types in it (`ServerInfo`, `LibraryInfo`,
  `Library`, `Book`, `BookRealm`, `BookReadingPosition`, `BookDeviceReadingPosition`
  old duplicate) had zero external references.
- **P2/A07 Providers.swift Dead Code Removal (Milestone A07):** Deleted 417
  lines of unreachable/deprecated code from `Providers.swift` and
  `RealmModel.swift`: `FolioReaderRealmPreferenceProvider` (replaced by
  `FolioReaderDelegatePreferenceProvider`), `FolioReaderHighlightRealm`
  (deprecated, not in Realm schema), `FolioReaderYabrHighlightProvider`
  (replaced by `FolioReaderDelegateHighlightProvider`),
  `FolioReaderReadPositionRealm` (deprecated, not in Realm schema), and the
  dead `extension FolioReaderHighlightRealm` in `RealmModel.swift`.
  `Providers.swift` shrank from 1095 to 708 lines.
- **P1/A09 DSReaderHelperConnector Thread Safety (Milestone A09):** Removed the
  `DispatchQueue.main.sync` call and redundant `URLCredentialStorage.shared.set`
  block from `DSReaderHelperConnector.urlSession`. Authentication is now handled
  solely by `CalibreServerTaskDelegate`'s challenge callback. Added
  `DSReaderHelperConnectorTests` (3 cases) for background-thread-safe access.
- **P2/A10 ShelfDataManager Move (Milestone A10):** Moved
  `ShelfDataManager.swift` (containing `YabrShelfDataModel` and the
  `ModelData.registerRecentShelfUpdater()`/`parseShelfSectionId` helpers) from
  `Views/ShelfView/` to `Models/`. The Xcode project was updated via
  `xcode_XcodeMV`, preserving both app and Catalyst target memberships. Pure
  file move, no declaration changes.
- **P2/A11 CalibreData Split (Milestone A11):** Decomposed the 1307-line
  `Models/CalibreData.swift` into ten focused files (see the Architecture Map
  `Models` section above) as a zero-behavior-change move. The original
  `CalibreData.swift` was deleted; all new files are registered in both app and
  Catalyst targets. Added `YetAnotherEBookReaderTests/CalibreDataSplitTests`
  (20 cases) covering `CalibreServer`/`CalibreLibrary` identity and hashing,
  `CalibreBook.inShelfId`, `BookHighlightStyle` class/color mapping, plugin
  preference Codable decoding, custom-column snake_case CodingKeys,
  `Array.chunks`, and the `CalibreActivity` class hierarchy.
- **P1f / MVVM Modernization (Milestone A08):** Successfully migrated high-traffic main screens out of monolithic `@EnvironmentObject var modelData` orchestration into focused, isolated ViewModels.
- **New ViewModels Introduced:**
  - `MainViewModel` (manages app shell tab selection, terms acceptance, book imports, and modal presentations).
  - `SettingsViewModel` (orchestrates server listings, staging deletion, reachability flags, and server replacements).
  - `SupportInfoViewModel` (decouples file-processing ZIP/backup operations and state tracking).
  - `RecentShelfViewModel` and `SectionShelfViewModel` (extract business flows out of UIKit/compositional shelf controllers).
- **LibraryInfo & Filter Consolidations:** Extended `LibraryInfoView.ViewModel` to handle search string alterations, category filtering, and count/status string derivations, eliminating direct `ModelData` reads in subviews.
- **Unit Testing Safety Net:** Added thorough, `@MainActor`-isolated unit tests covering `MainViewModelTests`, `SettingsViewModelTests`, `SupportInfoViewModelTests`, `RecentShelfViewModelTests`, `CalibreDataSplitTests`, and `DSReaderHelperConnectorTests` (total suite: 90 unit tests + 1 UI test).

Latest recorded verification in handoff notes:

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData
```

Recorded result: 159 unit tests and 1 UI test passed. The Mac Catalyst build is
currently blocked by a pre-existing SPM package product resolution issue
(`R2Navigator`, `GCDWebServer`, `R2Shared`, `R2Streamer`) that is unrelated to
the P1/P2 work.

## Known Risks

- `ModelData` remains a large compatibility facade. Small changes there can have
  large effects.
- Reader progress saving spans multiple engines. Verify shared reader behavior
  in all relevant reader paths.
- Realm threading mistakes usually appear only under background sync, search,
  shelf updates, or test concurrency.
- Search/category code has both legacy coordinator pieces and modern actor/value
  services. Prefer the modern services for new behavior.
- Xcode project file drift is easy when adding Swift files. Confirm target
  membership through build/test.
