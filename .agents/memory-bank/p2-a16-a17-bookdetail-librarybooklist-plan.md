# P2/A16+A17 Plan: BookDetailView And LibraryInfoBookListView Split

## Status

- **Plan date:** 2026-06-21
- **Scope:** A16 + A17 view decomposition after MVVM migration.
- **Current state:** Core logic has already moved into ViewModels, but two
  high-traffic view areas still have oversized composition files.
- **Goal:** Reduce SwiftUI view file size and responsibility without changing
  behavior, search semantics, download behavior, reader launch behavior, or
  Realm schema.

## Current Findings

### A16: BookDetailView Area

Current file sizes:

- `Views/BookDetailView/BookDetailView.swift`: 185 lines
- `Views/BookDetailView/BookDetailSubviews.swift`: 467 lines
- `Views/BookDetailView/BookDetailViewModel.swift`: 333 lines
- `Views/BookDetailView/BookPreviewView.swift`: 74 lines

The root view is much smaller than it used to be, but the complexity has mostly
settled into `BookDetailSubviews.swift`. That file currently owns unrelated
presentation pieces:

- `BookCoverView`
- `BookMetadataSection`
- `BookProgressSection`
- `BookConnectivitySection`
- `BookFormatList`
- `BookCountPagesCorner`

Remaining concerns:

- `BookProgressSection` still reaches into `ModelData.shared` for reading
  position lookups and disabled-state calculation.
- `BookDetailView` duplicates compact and regular layout assembly.
- `BookDetailView` still has stale helpers/state that should be audited:
  `previewViewModel`, `handleBookDeleted()`, and `generateCommentWithTOC(...)`.
- Sheet ownership is spread across subviews (`BookCoverView`,
  `BookProgressSection`, `BookConnectivitySection`, `BookFormatList`) via the
  same `BookDetailViewModel` presentation flags.
- `BookFormatList` mixes row rendering, download status, cache actions,
  preview setup, and sheet presentation in one view.

### A17: LibraryInfoBookListView Area

Current file sizes:

- `Views/LibraryInfoView/LibraryInfoBookListView.swift`: 432 lines
- `Views/LibraryInfoView/LibraryInfoViewModel.swift`: 197 lines
- `Views/LibraryInfoView/LibraryInfoBookRow.swift`: 171 lines
- `Views/LibraryInfoView/LibraryInfoBatchDownloadSheet.swift`: 101 lines
- `Views/LibraryInfoView/LibraryInfoBookListInfoView.swift`: 74 lines

`LibraryInfoView.ViewModel` already owns search criteria, sort criteria,
category filters, and category summary state. `UnifiedSearchViewModel` owns the
active search result and loading statuses. The list view still owns too much
screen orchestration:

- search field draft text and search history popover state
- selected rows and batch download list state
- batch download/info popover state
- grouped list construction
- toolbar construction
- footer status rendering
- row navigation existence check
- context menu filtering and actions
- debug diagnostics

Remaining concerns:

- `LibraryInfoBookListView` directly calls `modelData.bookExists`,
  `modelData.addToShelf`, and `modelData.startDownloadFormatNew`.
- Row grouping and section key calculation live in the view body path.
- Context menu filtering duplicates filter mutation concerns already present in
  `LibraryInfoView.ViewModel`.
- `LibraryInfoBookRow` handles infinite-scroll expansion in the row itself via
  `onAppear`, which makes the row less reusable and ties rendering to search
  pagination behavior.

## Non-Goals

- Do not redesign the UI.
- Do not change search/category algorithms or cache semantics.
- Do not change reader behavior, download behavior, or Calibre sync behavior.
- Do not introduce new persistence models or Realm migrations.
- Do not move new business logic back into `ModelData`.

## Target Shape

### BookDetailView Target

Recommended final files:

- `BookDetailView.swift`: root setup, loading state, top-level modifiers only.
- `BookDetailContentView.swift`: compact/regular layout selection and comments
  web view.
- `BookDetailToolbar.swift`: refresh, shelf/cache, and history toolbar buttons.
- `BookCoverView.swift`: cover, read/download launch affordance, reader sheet.
- `BookMetadataSection.swift`: static metadata rows and external links.
- `BookProgressSection.swift`: reading progress summary and history sheet.
- `BookConnectivitySection.swift`: sync status and activity log sheet.
- `BookFormatList.swift`: list container only.
- `BookFormatRow.swift`: one format row, cache/download/preview controls.
- `BookCountPagesCorner.swift`: Count Pages plugin summary.

Target responsibilities:

- `BookDetailViewModel` should expose any remaining view-ready values required
  to remove `ModelData.shared` access from `BookDetailSubviews`.
- Subviews should receive `BookDetailViewModel` and value inputs, not query
  global app state.
- Each extracted file should be mostly presentation-only and under roughly
  150-200 lines.

### LibraryInfoBookListView Target

Recommended final files:

- `LibraryInfoBookListView.swift`: root geometry shell and loading overlay only.
- `LibraryInfoBookListViewModel.swift`: list-local UI state and view actions.
- `LibraryInfoBookListHeader.swift`: search field, history trigger, active
  filter menu.
- `LibraryInfoBookListContent.swift`: list, empty state, grouped sections.
- `LibraryInfoBookListFooter.swift`: info popover, status text, count, refresh.
- `LibraryInfoBookListToolbar.swift`: download and sort controls.
- `LibraryInfoBookContextMenu.swift`: author/tag/series/download actions.
- `LibraryInfoBookRow.swift`: display-only row, with pagination callback
  passed in from the list content.

Target responsibilities:

- `LibraryInfoBookListViewModel` should own:
  - `selectedBookIds`
  - `downloadBookList`
  - `searchDraft`
  - `batchDownloadSheetPresenting`
  - `booksListInfoPresenting`
  - `searchHistoryPresenting`
  - section building for string/rating grouping
  - row action wrappers such as download/add-to-shelf
- `LibraryInfoView.ViewModel` should keep owning durable search criteria and
  category filters.
- `UnifiedSearchViewModel` should keep owning active search execution, statuses,
  and limit expansion.
- `LibraryInfoBookRow` should no longer call
  `expandSearchUnifiedBookLimit()` directly; the content view should pass a
  `onNearEnd(index:)` callback.

## Implementation Stages

Each stage should leave the app buildable and should be independently
reviewable.

### Stage A16-S1: Split BookDetail Composition Files

- Extract `BookDetailContentView` and `BookDetailToolbar` from
  `BookDetailView.swift`.
- Move each existing `BookDetailSubviews.swift` struct into its own file without
  behavioral edits.
- Delete `BookDetailSubviews.swift` once all declarations are moved.
- Preserve target membership for app and Catalyst.

Validation:

- `xcodebuild ... build`
- Existing `BookDetailViewModelTests`
- Manual smoke: open book detail in compact and regular layouts.

Exit criteria:

- `BookDetailView.swift` is root-only and under roughly 100 lines.
- No behavior changes beyond file movement.

### Stage A16-S2: Remove Global Reads From BookDetail Subviews

- Add view-ready helpers to `BookDetailViewModel` for reading progress summary
  and history availability.
- Update `BookProgressSection` to use the ViewModel rather than
  `ModelData.shared`.
- Audit `BookConnectivitySection` and `BookFormatList` for any remaining global
  or direct app-state reads.
- Add focused `BookDetailViewModelTests` for progress-summary cases:
  Goodreads read date, Goodreads progress, local device progress, no history.

Validation:

- `BookDetailViewModelTests`
- `xcodebuild ... build`

Exit criteria:

- Book detail subviews do not directly access `ModelData.shared`.

### Stage A16-S3: Isolate Format Row And Preview State

- Split `BookFormatList` into a container plus `BookFormatRow`.
- Keep preview sheet ownership at a single level, preferably the list container,
  so row controls only request preview.
- Move any preview-display strings or state reset helpers into
  `BookDetailViewModel` where they can be unit tested.
- Remove stale root helpers/state if confirmed unused:
  `BookDetailView.previewViewModel`, `handleBookDeleted()`, and
  `generateCommentWithTOC(...)`.

Validation:

- `BookDetailViewModelTests`
- `xcodebuild ... build`
- Manual smoke: cache, clear, pause/resume/cancel download, preview cached
  format.

Exit criteria:

- `BookFormatList.swift` and `BookFormatRow.swift` are presentation-focused and
  small enough to review independently.

### Stage A17-S1: Introduce LibraryInfoBookListViewModel

- Add `LibraryInfoBookListViewModel` for list-local UI state only.
- Keep search criteria in `LibraryInfoView.ViewModel`.
- Move local state from `LibraryInfoBookListView` into the new ViewModel:
  selection, draft search text, popover booleans, and batch download list.
- Add wrapper methods:
  - `syncDraftFromCriteria(_:)`
  - `submitSearch(libraryInfoViewModel:searchViewModel:)`
  - `clearSearch(libraryInfoViewModel:searchViewModel:)`
  - `prepareBatchDownload(books:)`

Validation:

- New `LibraryInfoBookListViewModelTests`
- `xcodebuild ... build`

Exit criteria:

- `LibraryInfoBookListView` has no local `@State` except possibly
  `@StateObject private var listViewModel`.

### Stage A17-S2: Extract Header, Footer, And Toolbar

- Extract `LibraryInfoBookListHeader`.
- Extract `LibraryInfoBookListFooter`.
- Extract `LibraryInfoBookListToolbar` or smaller toolbar controls if that fits
  SwiftUI constraints better.
- Keep active filter removal and sort actions routed through
  `LibraryInfoView.ViewModel` methods.
- Move footer status text calculation behind existing
  `LibraryInfoView.ViewModel` helpers or thin list ViewModel forwarding.

Validation:

- `LibraryInfoBookListViewModelTests`
- Existing unified search/category tests
- `xcodebuild ... build`

Exit criteria:

- Header/footer/toolbar can be reviewed without reading list row rendering.

### Stage A17-S3: Extract List Content And Section Building

- Add a small section model, for example:
  `LibraryInfoBookSection(id:title:items:)`.
- Move grouping by library/author/tag/rating out of the SwiftUI body and into
  `LibraryInfoBookListViewModel`.
- Extract `LibraryInfoBookListContent` to own empty state, sections, debug
  diagnostics, and near-end pagination callback.
- Keep `UnifiedSearchViewModel.expandSearchUnifiedBookLimit()` outside
  `LibraryInfoBookRow`.

Validation:

- Unit tests for section building:
  ungrouped, string group, rating group, empty result.
- Existing `UnifiedSearchServiceTests` and `UnifiedSearchIntegrationTests`
- `xcodebuild ... build`

Exit criteria:

- `LibraryInfoBookListView` no longer builds grouped dictionaries inside the
  SwiftUI body.
- `LibraryInfoBookRow` becomes display-only.

### Stage A17-S4: Extract Context Menu And Download Actions

- Extract `LibraryInfoBookContextMenu`.
- Move author/tag/series filter action construction into the list ViewModel or
  reusable value helpers.
- Route download/add-to-shelf actions through the list ViewModel so the context
  menu does not call `ModelData` directly.
- Preserve current behavior for in-shelf overwrite downloads and not-in-shelf
  add-to-shelf downloads.

Validation:

- Unit tests for context-action eligibility:
  excluded existing author/tag filters, series filter, formats list.
- Manual smoke: context menu filters and download actions.
- `xcodebuild ... build`

Exit criteria:

- `LibraryInfoBookListView` contains no context menu implementation details.

### Stage A17-S5: Final Cleanup And Regression Sweep

- Remove stale debug prints from touched views unless intentionally retained
  under `#if DEBUG`.
- Confirm all new files are in both app and Catalyst targets.
- Update `AGENTS.md` or active context only if architecture guidance changes.
- Run full validation.

Validation:

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData
```

Exit criteria:

- Full test suite passes or any unrelated failure is documented with a
  reproducible baseline.
- `BookDetailView.swift` and `LibraryInfoBookListView.swift` are small
  composition roots.
- No new direct Realm or `ModelData.shared` reads are introduced in SwiftUI
  subviews.

## Test Plan

Minimum targeted tests to add:

- `BookDetailViewModelTests`
  - progress summary selection
  - history availability
  - preview TOC state reset if preview behavior changes
- `LibraryInfoBookListViewModelTests`
  - draft search submit/clear
  - batch download preparation
  - grouping by string keys and rating
  - footer/status forwarding
  - context action eligibility

Existing tests to keep green:

- `BookDetailViewModelTests`
- `UnifiedSearchServiceTests`
- `UnifiedSearchIntegrationTests`
- `UnifiedCategoryServiceTests`
- `V2MigrationDependencyTests`

## Risks

- SwiftUI sheet ownership can regress if the same presentation flag is moved to
  multiple extracted views. Keep one owner per sheet.
- `BookDetailViewModel` still depends on Realm-backed `CalibreBookRealm` setup.
  Avoid moving live Realm objects across async boundaries while adding helpers.
- `LibraryInfoBookListView` sits at the intersection of
  `LibraryInfoView.ViewModel`, `UnifiedSearchViewModel`, `ModelData`, and
  `BookDownloadManager`; move one responsibility at a time.
- `LibraryInfoBookRow` currently triggers pagination on row appearance. Moving
  this to the list content must preserve near-end expansion behavior.

## Recommended Order

1. A16-S1: zero-behavior file split for BookDetail.
2. A16-S2: remove global reads from BookDetail subviews.
3. A16-S3: isolate format row and preview state.
4. A17-S1: introduce list-local ViewModel.
5. A17-S2: extract header/footer/toolbar.
6. A17-S3: extract list content and grouping.
7. A17-S4: extract context menu and row actions.
8. A17-S5: final cleanup and full regression.
