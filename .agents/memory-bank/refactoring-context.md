# Refactoring Analysis Context

## Date: 2026-06-06

## Latest Update: 2026-06-17

## P1e Implementation: 2026-06-17

P1e is now implemented. The V2 search/category stack is the application root dependency graph, and the V1 `CalibreBrowser` path has been removed rather than wrapped.

### Delivered Structure

- `ModelData` now owns and wires:
  - `searchCacheRepository: RealmSearchCacheStore`
  - `librarySearchService: LibrarySearchService`
  - `unifiedSearchService: UnifiedSearchService`
  - `categoryCacheRepository: CategoryCacheRepository`
  - `libraryCategoryService: LibraryCategoryService`
  - `unifiedCategoryService: UnifiedCategoryService`
- `YabrShelfDataModel` now depends directly on `UnifiedSearchService`.
- `UnifiedSearchViewModel`, `UnifiedCategoryViewModel`, `LibraryInfoView.ViewModel`, and `CalibreLibraryManager` now resolve V2 services and repositories directly from `ModelData`.

### Removed V1 Surface

- Deleted `Models/CalibreBrowser/CalibreBrowser.swift`
- Removed `CalibreLibrarySearchManager` from `ModelData`
- Removed the old V1-only runtime/cache orchestration layer and helper types, including:
  - `CalibreLibrarySearchRuntime`
  - `CalibreUnifiedCategoryObject`
  - `CalibreUnifiedCategoryItemObject`
- Deleted the `searchLibraryBooks(task:)` path by making `LibrarySearchService` the search execution boundary and moving request construction into `Network/CalibreServerService+Search.swift`

### Shared Types Preserved

Search/category value types that are still valid in V2 were retained and moved to neutral locations:

- `UnifiedSearchModels.swift`
  - `LibrarySearchSort`
  - `SortCriteria`
  - `SearchCriteria`
  - `SearchCriteriaMergedKey`
- `CategoryModels.swift`
  - `LibraryCategoryList`
  - `LibraryCategoryListResult`

### Persistence / Migration Changes

- Realm schema version advanced from `138` to `139`
- Added one-time migration cleanup:
  - `migration.deleteData(forType: CalibreUnifiedCategoryObject.className())`
  - `migration.deleteData(forType: CalibreUnifiedCategoryItemObject.className())`
- Removed the old `<110` unified-category field backfill branch because the deprecated object type no longer exists in the runtime schema

### Test Coverage Added

- `V2MigrationDependencyTests`
  - verifies `UnifiedSearchViewModel` defaults to `ModelData.unifiedSearchService`
  - verifies `UnifiedCategoryViewModel` defaults to `ModelData.unifiedCategoryService`
  - verifies `LibraryInfoView.ViewModel.fetchAvailableCategories()` uses `categoryCacheRepository`
  - verifies `YabrShelfDataModel.refresh()` resets active unified searches through `UnifiedSearchService`
- Updated `UnifiedSearchIntegrationTests` to construct and inject V2 services directly instead of using `CalibreLibrarySearchManager`

### Verification

- Build:
  - `xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17'`
- Tests:
  - `xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17'`
- Latest result: 55 unit tests + 1 UI test passed

## P1d A04 Plan: 2026-06-17

The next high-value refactoring target is `CalibreServerService.swift` (1436 lines). The goal is not a cosmetic split, but to turn the file into a maintainable network boundary with explicit error semantics and endpoint-local responsibilities.

### P1d Objectives

- Introduce a unified `CalibreAPIError` to replace scattered `NSError`, silent `try?` decode failures, and ad hoc HTTP error handling.
- Add a shared request execution layer that performs URL loading, HTTP status validation, payload presence checks, decode error mapping, and transport error conversion.
- Split endpoint logic by domain while preserving existing public `CalibreServerService` facade methods to avoid large call-site churn.

### Planned File Layout

- `Network/CalibreAPIError.swift`
- `Network/CalibreServerService.swift`
  - keep session management, shared state, and compatibility facade methods
- `Network/CalibreServerService+LibrarySync.swift`
- `Network/CalibreServerService+Metadata.swift`
- `Network/CalibreServerService+Discovery.swift`
- `Network/CalibreServerService+ReadingPosition.swift`
- `Network/CalibreServerService+Annotations.swift`

### Endpoint Grouping Strategy

Read-only endpoints first:

- Library sync and book list fetch
- Metadata fetch
- Probe / reachability
- Custom columns / library categories

Write endpoints second:

- Set last read position
- Update annotations
- Metadata update

### Error Model Scope

`CalibreAPIError` should cover at least:

- `invalidURL`
- `transport(URLError)`
- `httpStatus(Int, Data?)`
- `decoding(Error)`
- `emptyResponse`
- `authFailed`
- `serverRejected(String?)`
- `unsupportedPayload`
- `unknown`

### Implementation Order

1. Define `CalibreAPIError`.
2. Extract a shared request helper and centralize error mapping.
3. Split read-only endpoint implementations into dedicated extensions.
4. Split write endpoint implementations into dedicated extensions.
5. Collapse duplicated async and Combine code paths onto shared internal request/decode helpers.
6. Keep old public entry points as wrappers until call sites can be migrated safely.

### Constraints and Risks

- The largest risk is async/Combine drift: many endpoints currently exist in both forms, and splitting without sharing internals would preserve duplication.
- The second risk is that explicit error propagation will surface currently silent failures; the facade layer should preserve compatibility first, then calling layers can be tightened later.
- This phase should not simultaneously rewrite `ModelData` dependencies or re-architect URLSession management.

## P1d A04 Implementation: 2026-06-17

P1d-A04 is now implemented.

### Delivered Structure

- `Network/CalibreAPIError.swift`
- `Network/CalibreServerService.swift`
  - retains session/config state and shared request helpers
- `Network/CalibreServerService+LibrarySync.swift`
- `Network/CalibreServerService+Metadata.swift`
- `Network/CalibreServerService+Discovery.swift`
- `Network/CalibreServerService+ReadingPosition.swift`
- `Network/CalibreServerService+Annotations.swift`

### Shared Layer Added

`CalibreServerService.swift` now centralizes:

- reachable endpoint URL construction
- JSON request construction
- async validated HTTP loading
- Combine validated HTTP loading
- status-code validation and transport mapping
- typed payload decoding through `CalibreAPIError`

### Compatibility Notes

- Existing public facade methods were preserved.
- Async and Combine endpoint implementations now share the same validation/error mapping path for the split domains.
- `getCustomColumnsPublisher` keeps compatibility by surfacing 4xx response bodies back into `CalibreSyncLibraryResult.errmsg`.

### Test Coverage Added

- `CalibreServerServiceTests.testValidatedDataMapsUnauthorizedToAuthFailed`
- `CalibreServerServiceTests.testGetCustomColumnsPublisherReturnsServerBodyAsErrmsg`

### Verification

- Targeted validation: `xcodebuild test ... -only-testing:YetAnotherEBookReaderTests/CalibreServerServiceTests`
- Full validation: `xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData`
- Latest result: 51 unit tests + 1 UI test passed.

P1b-A03 (`YabrPDFViewController` dismantling) has advanced substantially. The original PDF reader controller was reduced from 1716 lines to 311 lines. Responsibilities are now split across:

- `PDFAnnotationManager` — PDF highlight/annotation operations
- `PDFBookmarkManager` — PDF bookmark operations
- `PDFSearchController` — PDF search state and async search execution
- `PDFMarginCropController` — margin crop, visible-content bounds cache, blank overlay, and pixel scanning
- `YabrPDFViewController+Chrome` — reader chrome, navigation bar, toolbar, title view, thumbnail preview constraints
- `YabrPDFViewController+Navigation` — TOC list, page-change handling, reading progress, position history
- `YabrPDFViewController+Options` — reader preference application, scaling, display box, ReaderEngineController conformance
- `YabrPDFViewController+Selection` — text-selection menu, dictionary action, highlight action
- `YabrPDFViewController+Sharing` — original/annotated PDF sharing

Related commit: `2f26f2f refactor: split PDF view controller responsibilities`. Verified with `xcodebuild build` and `xcodebuild test`: 40 unit tests + 1 UI test passed.

## P1c A14+A15 Confirmation: 2026-06-17

A15 (`Reader theme/preferences abstraction`) is implemented across the active reader engines:

- `ReaderEnginePreferences` defines the engine-neutral preference payload.
- PDF implements `ReaderEngineController.applyPreferences(_:)` in `YabrPDFViewController+Options`.
- Readium implements `ReaderEngineController.applyPreferences(_:)` in `YabrReadiumReaderViewController`.
- FolioReader implements `ReaderEngineController.applyPreferences(_:)` via `FolioReaderDelegatePreferenceProvider` and `EpubFolioReaderContainer`.
- `YabrEBookReader.Coordinator.readerEngine(_:didUpdatePreferences:)` persists engine-neutral updates into `ReadiumPreferenceRealm`, `PDFOptions`, or `FolioReaderPreferenceRealm`.

A14 (`Reader highlight/annotation abstraction`) is implemented for the shared model and persistence path:

- `ReaderEngineHighlight` defines the engine-neutral runtime payload.
- `BookHighlight` converts to/from `ReaderEngineHighlight` and Calibre annotation entries.
- `AnnotationRepository` is the shared storage/sync boundary.
- PDF applies highlights through `PDFAnnotationManager.applyHighlights(_:)`.
- FolioReader applies highlights through `FolioReaderDelegateHighlightProvider.applyHighlights(_:)`.
- `YabrEBookReader.Coordinator` persists add/remove highlight events via `AnnotationRepository`.

Important caveat: Readium currently conforms to `ReaderEngineController`, but `YabrReadiumReaderViewController.applyHighlights(_:)` is a stub with the comment that Readium highlight rendering is not yet implemented in the UI layer. Treat A14 as "shared abstraction and storage complete; Readium rendering pending" if the acceptance criterion requires visible restored highlights in all three engines.

## Summary
A comprehensive architectural analysis was performed on the entire YetAnotherEBookReader codebase (28,702 Swift lines, 88 files).

## Key Findings

### Top 5 Critical Issues (P0)
1. **ModelData God Object** (2180 lines, 18 @Published properties) — needs splitting into 5-7 service classes
2. **Zero test coverage** — only 1 placeholder test exists
3. **RealmSwift leaked into 36 files** including 20+ view files — needs Repository pattern

### Architecture Stats
- Schema version: 137 (very high migration debt)
- `CalibreLibrarySearchManager` is the class in `CalibreBrowser.swift` (2137 lines)
- FolioReaderKit used via 7 files, Readium via 10 files (ReadiumShared + ReadiumNavigator)
- Reading position save/restore is triplicated across 3 reader engines
- V2 migration started but only covers search (156 lines vs V1's 2137 lines)

### Refactoring Plan
Full plan at: `~/.gemini/antigravity/brain/6899dc7b-d068-4b64-98ae-678c877182ce/REFACTOR_PLAN.md`

### Key Class Names (for future reference)
- `ModelData` — central state (Models/ModelData.swift)
- `CalibreLibrarySearchManager` — search/browse engine (Models/CalibreBrowser/CalibreBrowser.swift)
- `CalibreServerService` — network API (Network/CalibreServerService.swift)
- `BookDownloadManager` — download management (Network/BookDownloadManager.swift)
- `YabrPDFViewController` — PDF reader coordinator (Views/PDFView/YabrPDFViewController.swift, 311 lines after P1b-A03 split)
- `YabrReadiumReaderViewController` — Readium reader (Views/ReadiumView/, 747 lines)
