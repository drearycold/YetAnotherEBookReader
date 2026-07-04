# Legacy Completed Tasks And Milestones

Archived completed checklists and older cross-cutting context that no longer belongs in activeContext.md.

Source: split from `.agents/memory-bank/activeContext.md` on 2026-07-03. Entries are preserved as historical records unless this file explicitly says otherwise.

## Recent Changes & Decisions

- **Stage P4: Eliminate App Startup & Redraw Duplicate ViewModel Instantiations (2026-06-27, complete):** Fixed repeated ViewModel initialization by passing persistent `container` reference to `MainView` and `SettingsView` and wrapping ViewModel creation inside `@StateObject(wrappedValue:)` in their initializers. Wrapped `LibraryDetailView`, `libraryRestoreHiddenView`, and `ActivityList` in `LazyView` inside navigation links to prevent eager destination evaluation on parent redraws. Verified that all 365 unit tests and 1 UI test passed.
- **P2/SettingsView Add Server Navigation Loop Resolved (2026-06-21):** Resolved the Add Server sheet dismissal and immediate re-presentation loops in `SettingsView`. Refactored `AddModServerView` and `ServerViewModel` to accept and handle optional `CalibreServer?` parameters, allowing the "Add Server" form to pass `.constant(nil)` and eliminating the need for `dummyServer` mock instances. Validated with a full `xcodebuild test` run (122 unit tests + 1 UI test passed).
- **P1f / MVVM Modernization Completed (2026-06-18):** Enforced clean MVVM pattern on the highest traffic views (`MainView`, `SettingsView`, `SupportInfoView`, `RecentShelfController`, and `SectionShelfController`) to resolve monolithic state trapping in SwiftUI view bodies and UIKit controllers. Introduced `MainViewModel`, `SettingsViewModel`, `SupportInfoViewModel`, `RecentShelfViewModel`, and `SectionShelfViewModel` with thorough `@MainActor`-isolated unit tests covering actions, state, and mutations. Consolidated LibraryInfo child-view commands into the existing V2 ViewModels. Verified the entire project compiles successfully and runs with 67 unit tests + 1 UI test green.
- **Development Environment Migration:** Transitioning the project to an agent-first development workflow using the Google Antigravity CLI.
- **MCP Integration:** Moved Xcode toolchain configurations to `.agents/mcp_config.json` to allow the Antigravity CLI to autonomously interact with `xcodebuild` and the iOS Simulator.

## Archived Active Tasks

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
- [x] 38. Corrected the FolioReader font size mapping alignment with unified preferences (index 3/"20px" as 100%).
- [x] 39. Implemented all 5 performance optimization fixes to eliminate Realm database hangs and UI freezes when opening `BookDetailView`.
- [x] 40. Continued P1b-A03 by splitting `YabrPDFViewController` into dedicated extension files for chrome, navigation/progress, options, selection, and sharing, plus `PDFMarginCropController` for margin crop and blank overlay handling. Committed as `2f26f2f`.
- [x] 41. Confirmed P1c A14+A15 status: A15 theme/preferences abstraction is complete across PDF, Readium, and FolioReader; A14 highlight abstraction/storage is complete for shared model plus PDF/FolioReader application, with Readium highlight UI rendering still explicitly stubbed.
- [x] 42. Added `YabrPDFViewControllerTests` for core controller coordination behavior and verified them under `xcodebuild test`.
- [x] 43. Fixed `RealmReadingPositionRepository` cross-thread Realm reuse and added `ReadingPositionRepositoryThreadingTests`; full test suite now passes again.
- [x] 44. Execute P1d-A04: refactor `CalibreServerService` by introducing `CalibreAPIError`, extracting a shared request/error-mapping layer, and splitting endpoint logic by domain while preserving facade compatibility. Added `CalibreServerServiceTests` and verified with `xcodebuild test` (51 unit tests + 1 UI test).
- [x] 45. Execute P1e: promote V2 search/category services to `ModelData`, remove `CalibreLibrarySearchManager` / `CalibreBrowser.swift`, delete V1 unified category Realm models, add migration cleanup for schema `139`, and verify the direct V2 dependency graph with `V2MigrationDependencyTests`. Full validation now passes with 55 unit tests + 1 UI test.
- [x] 46. Execute P2/A11: split `Models/CalibreData.swift` (1307 lines) into ten focused model/payload/task/plugin/activity files, delete the original file, register all new files in both app and Catalyst targets, and add `CalibreDataSplitTests` (20 cases) covering identity/hashing, `inShelfId`, `BookHighlightStyle` mapping, plugin preference Codable decoding, custom-column CodingKeys, `Array.chunks`, and `CalibreActivity` hierarchy. Full validation green: 87 unit tests + 1 UI test.
- [x] 47. Execute P2/A10: move `ShelfDataManager.swift` from `Views/ShelfView/` to `Models/` via `xcode_XcodeMV`, preserving both app and Catalyst target memberships and making no declaration changes. Verified with `xcodebuild build` and full `xcodebuild test` (87 unit tests + 1 UI test green).
- [x] 48. Execute P1/A09: remove `DispatchQueue.main.sync` and redundant `URLCredentialStorage.shared.set(...)` from `DSReaderHelperConnector.urlSession`; rely on `CalibreServerTaskDelegate` for auth. Added `DSReaderHelperConnectorTests` (3 cases) for background-thread safety. Full validation green: 90 unit tests + 1 UI test.
- [x] 49. Execute P2/A07: delete 417 lines of dead/deprecated code from `Providers.swift` (`FolioReaderRealmPreferenceProvider`, `FolioReaderHighlightRealm`, `FolioReaderYabrHighlightProvider`, `FolioReaderReadPositionRealm`) and `RealmModel.swift` (`extension FolioReaderHighlightRealm`). No Realm schema change. Full validation green: 90 unit tests + 1 UI test.
- [x] 50. Execute P2/A13: delete the entire 378-line `Models/Book.swift` (not registered in Xcode project, never compiled, zero external references to any of its 7 types). Full validation green: 90 unit tests + 1 UI test.
- [x] 51. Execute P2/A22: remove 4 deprecated `@Persisted` properties from `CalibreLibrarySearchObject` in `CalibreSearchCache.swift`. Bump Realm schema version 139→140 (update `ModelData.RealmSchemaVersion`, `CFBundleVersion` in both Info.plist files, and migration block). Full validation green: 90 unit tests + 1 UI test.
- [x] 52. Execute P2/A23: convert `DatabaseService.realmConf` and `realm` from force-unwrapped optionals (`!`) to regular optionals (`?`), replace `try!` in `setup()` with `do/catch` + `OSLog.Logger` error logging. Fix `LibrarySearchService.getRealm()` to guard-unwrap `realmConf`. Full validation green: 90 unit tests + 1 UI test.
- [x] 53. Execute FolioReader Highlight Position Restore Fix (2026-06-23): call `encodeContents()` in `BookHighlight.toFolioReaderHighlight()`, route `EpubFolioReaderContainer.applyHighlights` through the protocol method to lazily create the provider, add `ensureEncoded` last-line guard. Added 4 regression tests in `FolioReaderProviderBookIdTests`. Full validation green: 191 tests.
- [x] 53. Execute P2/A12+A24: split monolithic `RealmModel.swift` into individual, focused model files under `Models/Realm/`, relocate `FolioReaderPreferenceRealm` from views to models, and extract Readium preference mappings from `ReadiumPreferenceRealm` into the rendering layer `ReadiumPreferenceAdapter.swift` to decouple the core model layer from Readium dependencies. Full validation green: 90 unit tests + 1 UI test.
- [x] 54. Execute P2/A19 Stage A19-S1: route calibre category HTTP requests in `LibraryCategoryService` through `validatedData` to verify HTTP status codes, preserve local scheme fallback, and add a status failure test to verify cache safety. Full validation green: 91 unit tests + 1 UI test.
- [x] 55. Execute FolioReader Position Restore Race Fix (2026-06-23): make `RealmReadingPositionRepository.savePosition(_:forBookId:)` replace older same-identity positions atomically within one Realm write transaction, preventing FolioReaderKit reload reads from observing a transient empty position set. Added focused repository/provider/concurrency regression tests. Full `xcodebuild test` validation green.
- [x] 56. Execute repository Combine output removal (2026-07-02): converted repository observer APIs in `BookRepository`, `LibraryRepository`, `AnnotationRepository`, `CategoryCacheRepository`, and `RealmSearchCacheStore` from Combine publishers to `AsyncStream`, deleted the unused search-cache publisher API, and migrated production consumers (`BookDetailViewModel`, `ActivityListViewModel`, `LibraryViewModel`, `LibraryInfoView.ViewModel`, `UnifiedCategoryViewModel`) to cancellable tasks. Realm observations now use `Results.observe(...)` with token invalidation on stream termination. Focused validation green for `RealmBookRepositoryTests`, `BookDetailViewModelTests`, `LibraryViewModelTests`, `UnifiedCategoryServiceTests`, `UnifiedSearchServiceTests`, and `V2MigrationDependencyTests`; repository/protocol Combine scan is clean; `git diff --check` and the standard iOS Simulator build both pass.

## Archived Completed Refactoring Milestones

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
- [x] Consolidate reading position saving logic across Readium, FolioReader, and PDF engines (Milestone P1a-A06).
- [x] Unify reader theme/preferences abstraction across PDF, Readium, and FolioReader (Milestone P1c-A15).
- [x] Unify reader highlight/annotation model and storage abstraction, with Readium UI rendering still tracked as a remaining implementation caveat (Milestone P1c-A14).
- [x] Dismantle PDF God VC by extracting Annotation, Bookmark, Search, Margin Crop, Chrome, Navigation, Options, Selection, and Sharing responsibilities (Milestone P1b-A03).
- [x] Correct FolioReader font size mapping discrepancy and align with unified preferences.
- [x] Mitigate Realm database hangs/UI freezes when opening BookDetailView (Fixes 1-5).
- [x] Remove books property from CalibreLibrarySearchValueObject and dynamically resolve books list.
- [x] Split `Models/CalibreData.swift` into ten focused files (Milestone P2/A11) and add boundary tests for identity, Codable, and style mappings.
- [x] Move `ShelfDataManager.swift` from `Views/ShelfView/` to `Models/` (Milestone P2/A10), preserving both app and Catalyst target memberships.
- [x] Fix `DSReaderHelperConnector.urlSession` thread safety by removing `DispatchQueue.main.sync` and redundant credential storage (Milestone P1/A09).
- [x] Remove ~417 lines of dead/deprecated code from `Providers.swift` and `RealmModel.swift` (Milestone P2/A07).
- [x] Delete the entire 378-line `Models/Book.swift` (not compiled, zero external references) (Milestone P2/A13).
- [x] Remove 4 deprecated `@Persisted` properties from `CalibreLibrarySearchObject` and bump Realm schema to 140 (Milestone P2/A22).
- [x] Convert `DatabaseService` force-unwrapped Realm properties to optionals and replace `try!` with error handling (Milestone P2/A23).
- [x] Fix FolioReader highlight position restore by calling `encodeContents()` in `BookHighlight.toFolioReaderHighlight()`, routing `EpubFolioReaderContainer.applyHighlights` through the protocol method, and adding `ensureEncoded` last-line guard (FolioReader Highlight Position Restore fix).
- [x] Split monolithic `RealmModel.swift` (1357 lines) into individual files under `Models/Realm/` and decouple model layer from Readium Navigator/Shared dependencies (Milestone P2/A12+A24).
- [x] Route calibre category HTTP fetches in `LibraryCategoryService` through `validatedData` and implement safety validation tests (Milestone P2/A19 Stage A19-S1).
- [x] Modernize Combine publishers for annotations, library sync, reading positions, and raw metadata to return `CalibreAPIError` and add deprecated adapters (Milestone P2/A19 Stage A19-S5).
- [x] Make annotations/position upload and task-builder failures visible by introducing throwing builders, error properties on task structures, and modern publishers (Milestone P2/A19 Stage A19-S6).
- [x] Shelf View Wood Theme Alignment - Stage S0: Freeze baseline screenshots and discrepancy checklists.
- [x] Shelf View Wood Theme Alignment - Stage S1: Establish Pure Layout & Presentation Contract.
- [x] Shelf View Wood Theme Alignment - Stage S2: Implement Reusable Shelf Tile Shell.
- [x] Shelf View Wood Theme Alignment - Stage S3: Migrate Cover, Fallback, and Spine.
- [x] Shelf View Wood Theme Alignment - Stage S4: Migrate Progress, Status, Options, and Edit Overlay.
- [x] Shelf View Wood Theme Alignment - Stage S5: Switch Recent Continuous Grid.
- [x] Shelf View Wood Theme Alignment - Stage S6: Handle Recent Safe Area, Tab Bar, and Edit Toolbar.
- [x] Shelf View Wood Theme Alignment - Stage S7: Switch Discover Header and Horizontal Shelf Row.
- [x] Shelf View Wood Theme Alignment - Stage S8: State Matrix and Interactive Regression.
- [x] Shelf View Wood Theme Alignment - Stage S9: Visual Acceptance and Full Verification.
