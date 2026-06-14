# Active Context

## Current Focus
The primary focus is the Modernization of the EBook Reader Architecture. We have completed milestones P0-1a (`CalibreServerManager`), P0-1b (`CalibreLibraryManager`), P0-1d (`CalibreBookManager`), P0-1e (`ReadingSessionManager`), P0-3a (`BookRepository`), P0-3b (`ServerRepository` and `LibraryRepository`), and P0-3c (`AnnotationRepository`) to modularize the application state, decouple network/management operations, and separate concerns. All 41 unit and UI tests are passing successfully.

## Recent Changes & Decisions
- **AnnotationRepository (Milestone P0-3c):** Introduced `BookBookmark` and `BookHighlight` value types and `RealmAnnotationRepository` to decouple bookmarks and highlights from direct `RealmSwift` database logic. Ported Calibre annotation sync logic from `CalibreData.swift` into the repository.
- **UI Adapters Decoupling:** Refactored PDF adapter `YabrEBookReaderMetaSource.swift` and FolioReader/EPUB adapter `Providers.swift` to consume decoupled value types `BookBookmark` and `BookHighlight` instead of their Realm model counterparts, keeping UI adapters and rendering pipelines decoupled from Realm entities. Added Calibre serialization extensions directly to the value types.
- **CalibreBookManager getRealm() Optimization:** Optimized the `getRealm()` helper in `CalibreBookManager.swift` to check `Thread.isMainThread` and return the cached `databaseService.realm` directly, preventing expensive Realm instance allocation on the main thread and ensuring UI reactivity.
- **ServerRepository and LibraryRepository (Milestone P0-3b):** Decoupled `CalibreServerManager` and `CalibreLibraryManager` completely from Realm database logic. Created `RealmServerRepository` and `RealmLibraryRepository` to isolate CRUD operations for Calibre servers and libraries. Extracted all direct database references from the managers, resulting in the total removal of `import RealmSwift` from both managers.
- **ReadingPositionService Extraction (Milestone P0-1e):** Successfully migrated format preferences (`defaultFormat`, `formatReaderMap`, `formatList`), reader preference logic, manual progress syncing (`updateCurrentPosition`), and reading session helper methods from `ModelData` into `ReadingSessionManager`. Replaced `@Published var sessionManager` with a `lazy var` and established thread-safe change notification forwarding via Combine.
- **ModelData Main Thread Notification Forwarding:** Integrated `.receive(on: DispatchQueue.main)` on manager `objectWillChange` subscriptions in `ModelData.init` to ensure all SwiftUI state-propagation updates originating from nested managers are delivered on the main thread, eliminating runtime background thread update warnings.
- **Realm Thread-Safety Resolution (CalibreBookManager):** Resolved the fatal Realm thread verification crash by replacing direct main-thread `databaseService.realm` references with a thread-safe `getRealm()` helper, ensuring background thread queries dynamically initialize thread-safe Realm instances. Annotated `getBooksMetadata(request:)` with `@MainActor` to ensure UI state updates are published on the main thread.
- **CalibreBookManager Extraction (Milestone P0-1d):** Extracted book-related properties (`booksInShelf`, `booksAnnotation`, `selectedBookId`, `bookModelSection`, etc.) and their management/CRUD methods out of `ModelData` into a dedicated `CalibreBookManager`. Forwarded `bookManager.objectWillChange` to `ModelData` and maintained computed property delegates for legacy compatibility.
- **CalibreLibraryManager Extraction (Milestone P0-1b):** Extracted library-specific state (`calibreLibraries`, `calibreLibraryInfoStaging`, `librarySyncStatus`, `localLibrary`) and their management methods out of `ModelData` into a dedicated `CalibreLibraryManager`. Provided backward-compatible delegate properties and methods, and updated ViewModels (`LibraryViewModel`, `ServerViewModel`) to subscribe directly to `CalibreLibraryManager` properties.
- **CalibreServerManager Extraction (Milestone P0-1a):** Extracted server-specific state (`calibreServers`, `calibreServerInfoStaging`, `documentServer`) and their management methods out of `ModelData` into a dedicated `CalibreServerManager`. Resolved a lazy loading dependency cycle by dynamically resolving `calibreServerService` via `modelData`.
- **ModelData Forwarding Compatibility:** Re-added backward-compatible forwarding properties and methods to `ModelData` to ensure legacy Views, ViewModels, and Tests still compile without large diffs. All 41 tests are verified green.
- **Cleanup of Duplicates:** Removed duplicate physical folders (`Managers 2`, `Managers 3`, `Managers 4`) from the workspace.
- **Unified Search Modernization (Phase 1):** Introduced immutable domain value types (`UnifiedSearchResult`, `MergeOffset`, `LibrarySearchStatus`, `SearchError`) and decoupled the database via `SearchCacheRepository` and its concrete implementation `RealmSearchCacheStore`.
- **Unified Search Modernization (Phase 2):** Implemented in-memory K-way merging using Apple's `swift-collections` `Heap`.
- **Unified Search Modernization (Phase 3):** Introduced `UnifiedSearchManager` and `ActiveSearch` to orchestrate searches and merging in memory, and refactored `CalibreBrowser.swift` to delegate merging to `UnifiedSearchManager`.
- **Unified Search Modernization (Phase 4):** Refactored UI layer (Views and ViewModels) to consume `UnifiedSearchResult` via Combine, removing tight coupling to Realm objects like `CalibreUnifiedSearchObject`. Removed the $O(N)$ lookup `getMergedBookIndex()` logic in favor of straightforward array iteration.
- **Development Environment Migration:** Transitioning the project to an agent-first development workflow using the Google Antigravity CLI.
- **Architectural Shift (MVVM):** Transitioning from a single monolithic `@EnvironmentObject var modelData` to modular `@StateObject` ViewModels for complex views.
- **Context Guardrails:** Established the `.agents/memory-bank` directory to provide strict architectural guidelines, preventing subagents from hallucinating or deviating from the Swift Package Manager / SwiftUI architecture.
- **MCP Integration:** Moved Xcode toolchain configurations to `.agents/mcp_config.json` to allow the Antigravity CLI to autonomously interact with `xcodebuild` and the iOS Simulator.

## Active Tasks
- [x] 1. Expand `BookDetailViewModel.swift` to handle all data fetching (metadata, manifest) and UI state variables currently trapped in `BookDetailView.swift`.
- [x] 2. Break down the massive `BookDetailView.swift` (800+ lines) into smaller, manageable subcomponents (`BookDetailSubviews.swift`).
- [x] 3. Replace direct `ModelData` network calls inside `BookDetailView` with unidirectional data flow via `BookDetailViewModel`.
- [x] 4. Compile the project in the terminal using `xcodebuild` to ensure the SwiftUI refactoring doesn't break the build and unit tests pass.
- [x] 5. Successfully decoupled `ModelData` from all `BookDetailView` subviews (`BookCoverView`, `BookMetadataSection`, `BookConnectivitySection`, `BookFormatList`, `BookProgressSection`) by passing state through `BookDetailViewModel`.
- [x] 6. Decoupled `BookDownloadManager` from `BookDetailView` and `BookDetailSubviews` by mapping `activeDownloads` into `BookDetailViewModel` using Combine.
- [x] 7. Decoupled `ModelData` from `BookDetailView`'s state presentation stack, book conversion, and metadata status, proxying them through `BookDetailViewModel`. Unit tests added and verified.
- [x] 8. Migrated presentation state variables (`presentingReadingSheet`, `presentingPreviewSheet`, `activityListViewPresenting`, `readingPositionHistoryViewPresenting`) from `BookDetailView` to `BookDetailViewModel`, utilizing custom Binding wrappers in property observers.
- [x] 9. Decoupled `BookDetailView` entirely from `@EnvironmentObject var modelData`, utilizing dependency injection of `ModelData.shared` inside the ViewModel.
- [x] 10. Enforced MVVM architecture on Reading Position views (`ReadingPositionHistoryView` and `ReadingPositionDetailView`), decoupling them from `ModelData` and Realm queries via `ReadingPositionHistoryViewModel` and `ReadingPositionDetailViewModel`.
- [x] 11. Enforced MVVM architecture on Activity Log views (`ActivityList` and `ActivityDetailView`), extracting Realm queries and resolution logic to `ActivityListViewModel` and exposing plain `ActivityLogUIEntry` structures.
- [x] 12. Fixed the `recent-shelf-updater` background thread Realm concurrency crash by caching `realmPerf` via thread-local storage (`Thread.current.threadDictionary`).
- [x] 13. Completed Unified Search modernization Phase 1: Created `UnifiedSearchModels.swift`, `SearchCacheRepository.swift`, and `RealmSearchCacheStore.swift`, and successfully integrated them into Xcode project and verified build.
- [x] 14. Completed Unified Search modernization Phase 2: Created `UnifiedSearchMergeService` and heap-based iterators.
- [x] 15. Completed Unified Search modernization Phase 3: Created `UnifiedSearchManager` and integrated it with `CalibreBrowser` to perform backend merging in memory. Resolved the background thread Realm notification registration crash in `RealmSearchCacheStore` by utilizing a Combine `Deferred` publisher on the main queue and mapping managed entities to thread-safe value structs. Fixed the infinite loop feedback cycles by adding equality check guards on limitNumber changes and caching the last processed library source search results to prevent redundant merge operations when Realm updates book metadata. Resolved the main thread deadlock by replacing the synchronous `cacheRealmQueue.sync` call in `getMergedBookIndex` with a lightweight, non-blocking `NSRecursiveLock` to protect the runtime dictionaries. Fixed the limit expansion issue by forcing a Realm database refresh on the background queue before reading the updated limit value.
- [x] 16. Resolved the empty libraryIds limit expansion issue in Unified Search (where "All Books" view had empty libraryIds, resulting in 0 merged books and a totalNumber of 0, which blocked limit expansion) by resolving empty libraryIds to all active calibre libraries in UnifiedSearchManager and UnifiedSearchMergeService. Added unit test verification.
- [x] 17. Resolved the Realm write transaction deadlock between main thread limit expansion and background merge updates by converting UnifiedSearchManager mutators (`setLimit`, `expandLimit`, `resetSearch`, `updateLibraryStatus`) to run asynchronously on its serial queue, preventing the blocking of `cacheRealmQueue`. Added asynchronous unit test synchronization.

- [x] 18. Executed Phase 4 of Unified Search modernization: Migrated the UI and ViewModels (e.g., `LibraryInfoBookListView`, `ShelfDataManager`, `LibraryInfoViewModel`) to use the new `UnifiedSearchManager` and removed legacy Realm bindings. Validated through Xcode build.
- [x] 19. Resolved the unit test race condition crash in `MockSearchCacheRepository` using `NSRecursiveLock` and solved the infinite loop in `UnifiedSearchManager` by making `selectActiveSource` sorting deterministic, partially updating `CalibreBookRealm` objects to preserve reading progress, and deduplicating duplicate `CalibreUnifiedSearchObject` and `CalibreLibrarySearchObject` records in Realm on startup.
- [x] 20. Execute Phase 5 of Unified Search modernization: Cleanup, final testing, and deletion of `CalibreUnifiedSearchObject` from the Realm Schema.
- [x] 21. Resolved the issue where changing search criteria (or clicking the manual refresh button) did not trigger search/network actions, by wiring `searchTriggerHandler` and updating `refreshSearchResults` to dynamically initialize and check cache for new search keys.
- [x] 22. Implemented comprehensive test coverage for the Unified Search subsystem, including unit tests for criteria isolation, pagination, sorting stability, and end-to-end integration tests using MockURLProtocol.
- [x] 23. Decouple `CalibreServerService` and remaining `ModelData` dependencies.
- [x] 24. Resolved Realm collection insertion exception (`RLMThrowCollectionException`) in `RealmSearchCacheStore.saveLibrarySourceResult` by creating/updating objects via `realm.create(_:value:update:)` with the `.modified` update policy. Resolved the testing deadlock under Swift Concurrency by aligning the Hashable contract of `CalibreServer` / `CalibreServerURLSessionKey` and migrating `UnifiedSearchServiceTests` to non-blocking `await fulfillment(of:timeout:)` expectations.
- [x] 25. Resolved all Code Review findings on commit `649cbc55`. Eliminated `DispatchQueue.main.sync` deadlocks in `CalibreServerService` and `UnifiedSearchService` via thread-safe configuration caching and async methods. Cleaned up debug print statements, dead variables, safely unwrapped `ModelData.shared`, deleted the orphaned `ActiveSearch.swift`, and verified that all 31 unit tests pass.
- [x] 26. Resolved the fatal nil-unwrap crash in `testEmptyLibraryIdsMergingAndExpansion` (Task 232) by removing redundant `ModelData` initialization and overrides in tests, since the mock library provider handles library lists.
- [x] 27. Decoupled `libraryStatuses` from `UnifiedSearchResult` by updating `UnifiedSearchService` to stream `SearchUpdate` value types and `UnifiedSearchViewModel` to publish statuses separately.
- [x] 28. Refactored search criteria and UI preferences to `LibraryInfoView.ViewModel`, removing criteria properties from `UnifiedSearchViewModel` and passing `SearchCriteriaMergedKey` to `startSearch(key:)` explicitly.
- [x] 29. Fixed the Combine bridge task leak in `publisher(for:)` by wrapping the subscription block inside `Deferred`.
- [x] 30. Bypassed the autoUpdate check in category fetching inside `ModelData.syncLibrary(request:)` to ensure calibre library categories are synced and populated on startup/probes even when autoUpdate ("Available when Offline") is disabled.
- [x] 31. Decoupled `LibraryInfoCategoryListView` and `LibraryInfoView` completely from `RealmSwift` by introducing `CategoryCacheSummary` value types and querying summaries via `CategoryCacheRepository` reactively inside the `LibraryInfoView.ViewModel`.
- [x] 32. Decoupled `LibraryInfoCategoryItemsView` completely from `RealmSwift` by implementing cache invalidation in the repository layer and exposing `forceRefreshCategory` in the `UnifiedCategoryViewModel`.
- [x] 33. Decoupled `BookDetailView` completely from `RealmSwift` by shifting Realm database queries and reactive observations to `BookDetailViewModel`.
- [x] 34. Fixed EnvironmentObject propagation crash in `LibraryInfoCategoryItemsView` and `LibraryInfoView` by explicitly injecting the `libraryInfoViewModel` environment object to `LibraryInfoBookListView`.
- [x] 35. Refactored ServerView components (`AddModServerView`, `ServerDetailView`, `ServerOptionsDSReaderHelper`, `LibraryDetailView`) to MVVM using two view models (`ServerViewModel` and `LibraryViewModel`), completely decoupling `LibraryDetailView` from Realm.
- [x] 36. Fixed `libraryRowBuilder` sync status UI in `ServerDetailView.swift` to display mutually exclusive status text instead of overlapping states.
- [x] 37. Refactored `ReaderOptionsView.swift` to strictly enforce the MVVM pattern by delegating preferred formats, reader types, and font import/deletion state to `ReaderOptionsViewModel`.

## Active Tasks
- [x] Extract `CalibreServerManager` out of `ModelData` (Milestone P0-1a).
- [x] Extract `CalibreLibraryManager` out of `ModelData` (Milestone P0-1b).
- [x] Extract `CalibreBookManager` out of `ModelData` (Milestone P0-1d).
- [x] Resolve Realm thread safety crash and main-thread publishing in CalibreBookManager.
- [x] Decouple category views completely from RealmSwift.
- [x] Decouple BookDetailView completely from RealmSwift.
- [x] Refactor ServerView components to MVVM.
- [x] Fix libraryRowBuilder sync status UI representation.
- [x] Refactor ReaderOptionsView to MVVM and register project files.
- [x] Extract ReadingPositionService (Milestone P0-1e) into ReadingSessionManager.
- [x] Introduce BookRepository (Milestone P0-3a) to encapsulate book database operations and remove presentation layer Realm dependency.
- [x] Decouple bookmarks and highlights (annotations) into AnnotationRepository (Milestone P0-3c) and refactor reader UI adapters.

## Active Constraints
- **Do NOT** introduce CocoaPods or modify workspace files; the project relies entirely on Swift Package Manager.
- **Decoupling Goal:** Views should minimize direct dependency on `ModelData` for network operations; logic should reside in dedicated ViewModels.
