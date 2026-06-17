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
  - `RecentShelfUI`
  - `SectionShelfUI`
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

- `CalibreData.swift`: value/domain types for servers, libraries, books, sync
  tasks, custom columns, plugin prefs, annotations payloads, and Calibre API
  result structures.
- `RealmModel.swift`: Realm object schema. Treat edits here as migration work.
- `YabrData.swift`: format, reader, reader-info, and app-specific value types.
- `BookFiles.swift`: import and local-file helpers.
- `BookPreference.swift`, `BookBookmark.swift`, `BookHighlight.swift`: reader
  preferences and annotation value types.

### Search And Category

The modern path is value-type/actor based. Do not revive direct
`CalibreUnifiedSearchObject` bindings in views.

- `CalibreLibrarySearchManager` in `Models/CalibreBrowser/CalibreBrowser.swift`
  is the legacy-compatible coordinator and service factory.
- `LibrarySearchService` performs per-library search, online/offline source
  selection, metadata fetch, and cache writes.
- `UnifiedSearchService` is an actor that coordinates active multi-library
  searches and streams `SearchUpdate`.
- `UnifiedSearchMergeService` merges per-library results in memory.
- `UnifiedCategoryService` and `UnifiedCategoryMergeService` merge category
  cache results.
- `UnifiedSearchViewModel` and `UnifiedCategoryViewModel` are the UI-facing
  adapters for LibraryInfo views.

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
- `Views/ShelfView/*`: recent/discover shelf UIKit adapters and shelf data model.
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

- `YabrPDFViewController` has been split substantially and the main controller
  was reduced to roughly 311 lines in the latest handoff context.
- PDF responsibilities have been moved into annotation, bookmark, search,
  margin-crop, chrome, navigation, options, selection, and sharing components.
- Recent related commit: `2f26f2f refactor: split PDF view controller responsibilities`.
- Tests were added for `YabrPDFViewController` coordination behavior and
  `ReadingPositionRepository` threading behavior.
- A nil unwrap in `YabrPDFViewController.applyHighlights(_:)` was fixed by lazy
  initializing `annotationManager`, `bookmarkManager`, and `searchController`.
- A `Realm accessed from incorrect thread` issue was fixed by opening Realm from
  the current thread using `Realm.Configuration` rather than reusing main-thread
  Realm instances.

Latest recorded verification in handoff notes:

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData
```

Recorded result: 49 unit tests and 1 UI test passed.

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
