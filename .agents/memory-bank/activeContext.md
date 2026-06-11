# Active Context

## Current Focus
The primary focus is the Modernization of the Unified Search Subsystem (`CalibreUnifiedSearchObject`). We are transitioning from Realm-based persistent objects to in-memory Value Types and introducing a clean Repository pattern for search cache management. We have completed Phase 1: Value Types & Repository Layer, Phase 2: In-Memory K-Way Merge, Phase 3: Service Layer Migration, and Phase 4: UI Consumer Migration.

## Recent Changes & Decisions
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
- [ ] 22. Decouple `CalibreServerService` and remaining `ModelData` dependencies.

## Active Constraints
- **Do NOT** introduce CocoaPods or modify workspace files; the project relies entirely on Swift Package Manager.
- **Decoupling Goal:** Views should minimize direct dependency on `ModelData` for network operations; logic should reside in dedicated ViewModels.

