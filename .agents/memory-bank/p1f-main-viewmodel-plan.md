# P1f Plan: Introduce ViewModels For Main Views (A08)

## Date

2026-06-18

## Goal

P1f/A08 should continue the MVVM migration by introducing ViewModel boundaries for the remaining high-traffic app views that still coordinate directly through `ModelData`. The goal is not to remove `ModelData` everywhere in one pass, but to make the main screens testable and to move user-flow orchestration out of SwiftUI/UIKit view bodies.

## Current State

Already mostly covered by ViewModels:

- `BookDetailView` uses `BookDetailViewModel`, with related `ActivityListViewModel`, `ReadingPosition*ViewModel`, and `BookPreviewViewModel`.
- Server/library detail screens use `ServerViewModel` and `LibraryViewModel`.
- Reader options use `ReaderOptionsViewModel`.
- Library search/category has V2 service-facing `LibraryInfoView.ViewModel`, `UnifiedSearchViewModel`, and `UnifiedCategoryViewModel`.

Still direct or partially direct:

- `MainView` owns app shell flow, import handling, first-run terms, ATT consent, alert/action-sheet construction, dismiss-all coordination, tab side effects, and reader presentation.
- `LibraryInfoBookListView`, `LibraryInfoBookRow`, `LibraryInfoBookListInfoView`, `LibraryInfoCategoryListView`, and `LibraryInfoCategoryItemsView` still read `ModelData` for book existence, selected book binding, library lookup, download/shelf actions, and loading text.
- `SettingsView` owns server list projection, delete confirmation state, refresh actions, server mutation orchestration, and row status derivation despite existing server detail ViewModels.
- `RecentShelfController` and `SectionShelfController` are UIKit controllers wired directly to `ModelData` subjects and commands.
- `SupportInfoView` owns export state and filesystem zipping logic inside the SwiftUI view.
- Reader adapters still use `ModelData` directly, but they are engine integration surfaces and should not be the first P1f target.

## Approach

Introduce focused ViewModels around main view workflows first, then shrink direct `ModelData` access in child views by passing value state and command closures. Keep `ModelData` as the composition root and compatibility facade for now. Avoid changing Realm schema, reader engine behavior, or the V2 search/category service graph during this milestone.

## Scope

In:

- Add ViewModels for `MainView`, `SettingsView`, `SupportInfoView`, and shelf UI adapters.
- Consolidate LibraryInfo child-view commands into existing LibraryInfo ViewModels or a small list-specific ViewModel.
- Convert direct view-level `ModelData` queries into published value state, bindings, or explicit command methods.
- Add focused unit tests for new ViewModel behavior.

Out:

- Removing `ModelData` from reader engine adapters.
- Rewriting `YabrEBookReaderRepresentable` or PDF/Readium/FolioReader internals.
- Replacing all UIKit shelf controllers with SwiftUI.
- Changing Realm schema or search/category cache models.
- Large visual redesign.

## Proposed ViewModel Boundaries

### 1. MainViewModel

Candidate file:

- `Views/MainViewModel.swift` or `Views/AppShell/MainViewModel.swift`

Responsibilities:

- Publish app-shell state: `activeTab`, `realmConfigurationAvailable`, `shouldShowWelcome`, reader presentation state, first-run terms state, book import action-sheet state, and alert item.
- Wrap app-flow commands: `onAppear()`, `onOpenURL(_:)`, `acceptTerms()`, `declineTerms()`, `dismissAll(completion:)`, `handleImportedBookAction(_:)`, `refreshRecentShelf()`, `refreshDiscoverShelf()`, `confirmForwardBackwardProgress()`.
- Subscribe to `bookImportedSubject` and `dismissAllSubject`.
- Keep ATT/UMP calls behind injectable closures or a small consent coordinator so unit tests do not call platform UI APIs.

Important details:

- `MainView` can still inject `ModelData`, `ReadingSessionManager`, `BookDownloadManager`, and `FontsManager` into child views.
- Do not hide scene-phase database initialization in this ViewModel; that currently belongs to `YetAnotherEBookReaderApp`.

### 2. LibraryInfo Main-View Refinement

Candidate files:

- Extend `Views/LibraryInfoView/LibraryInfoViewModel.swift`
- Optionally add `Views/LibraryInfoView/LibraryInfoBookListViewModel.swift`

Responsibilities to move out of child views:

- Book existence and navigation selection:
  - `bookExists(forPrimaryKey:)`
  - selected book id binding
- Download/shelf commands:
  - `cacheFormat(book:format:)`
  - `addBookToShelf(book:formats:)`
  - batch-download list preparation
- Library loading/status text:
  - `getLibraryLoadingCount()`
  - `getLibrarySearchingText()`
- Library lookup for info popover:
  - map `UnifiedSearchResult.unifiedOffsets` to display-ready library rows.
- Search/filter/sort/group commands:
  - `searchStringChanged(_:)`
  - `updateFilterCategory(key:value:)`
  - `applySort(_:)`
  - `toggleGroupBy(_:)`
  - `openCategoryItem(_:)`

Important details:

- Keep `UnifiedSearchViewModel` focused on search execution and streaming.
- Keep `LibraryInfoView.ViewModel` focused on criteria, category selection, and UI projection.
- If `LibraryInfoBookListViewModel` is introduced, make it a thin coordinator that depends on `LibraryInfoView.ViewModel`, `UnifiedSearchViewModel`, `BookDownloadManager`, and selected `ModelData` commands.

### 3. SettingsRootViewModel

Candidate file:

- `Views/SettingsView/SettingsViewModel.swift`

Responsibilities:

- Publish sorted `serverList`, `selectedServer`, `addServerActive`, `serverListDelete`, `alertItem`, and refresh/removal status.
- Derive server row display state:
  - DSReader Helper availability
  - private/public reachability
  - library count
  - processing count
  - server info/error text
- Wrap commands:
  - `refreshServers()`
  - `stageServerDeletion(_:)`
  - `cancelServerDeletion()`
  - `confirmDeleteServer()`
  - `updateServer(old:new:)`
  - `makeAddServerViewModel()`
  - `makeServerDetailViewModel(server:)`

Important details:

- Reuse existing `ServerViewModel` and `LibraryViewModel`.
- Do not duplicate server edit field logic already in `ServerViewModel`.
- Preserve current server replacement behavior, including library/server id migration and shelf reload, but isolate it for testing.

### 4. Shelf ViewModels / Controller Models

Candidate files:

- `Views/ShelfView/RecentShelfViewModel.swift`
- `Views/ShelfView/SectionShelfViewModel.swift`

Responsibilities:

- `RecentShelfViewModel`
  - Subscribe to `recentShelfModelSubject`.
  - Expose `[BookModel]`.
  - Wrap refresh commands.
  - Wrap book tap behavior: prepare reader, present detail when no suitable reader exists, delete selected books.
- `SectionShelfViewModel`
  - Subscribe to `discoverShelfModelSubject` and `shelfDataModel.discoverShelfSubject`.
  - Build filtered sections and library menu items as value state.
  - Wrap refresh and download-selected commands.
  - Keep snapshot building in controller if needed, but feed it value-only sections.

Important details:

- UIKit controllers should become adapters: layout, ads, navigation bar, and ShelfView delegate callbacks only.
- Keep `NSDiffableDataSourceSnapshot` construction in controllers until the value-state boundary is stable.

### 5. SupportInfoViewModel

Candidate file:

- `Views/SettingsView/SupportInfoViewModel.swift`

Responsibilities:

- Publish HTML availability, export state, export progress, current file, alert message, and folder picker state.
- Move `exportAppData(to:)` and `performZip(destinationURL:)` out of `SupportInfoView`.
- Provide injectable filesystem/archive collaborators later if tests need to avoid real directories.

Important details:

- `SupportInfoView` should only bind controls and sheets.
- Keep `FolderPicker` as the UI adapter.

## Implementation Order

1. Add `MainViewModel` and move import/dismiss/terms/tab side-effect logic out of `MainView`.
2. Add `SettingsViewModel` and refactor `SettingsView` to render server rows from derived display state.
3. Extend LibraryInfo ViewModels or add `LibraryInfoBookListViewModel` to remove direct `ModelData` use from list/info/category child views.
4. Add `SupportInfoViewModel` and move export/zip state and async work out of `SupportInfoView`.
5. Add shelf ViewModels for recent/discover shelves and convert UIKit controllers into value-state adapters.
6. Sweep remaining main-view `@EnvironmentObject var modelData` usage and classify leftovers as either intentional composition-root access or follow-up reader-adapter work.

## Action Items

[ ] Add `MainViewModel` with published app-shell/import/terms state and injectable consent/report URL hooks.
[ ] Refactor `MainView` to bind to `MainViewModel` while keeping environment-object injection for child screens.
[ ] Add `SettingsViewModel` and `ServerRowState`, then move server list sorting, deletion, refresh, and server replacement commands out of `SettingsView`.
[ ] Refactor LibraryInfo child views to use existing criteria/search ViewModels plus a list-specific command surface instead of direct `ModelData` reads.
[ ] Add `SupportInfoViewModel` and move backup export progress and ZIP workflow out of `SupportInfoView`.
[ ] Add `RecentShelfViewModel` and `SectionShelfViewModel` to own shelf subjects, refresh commands, and book-tap/download commands.
[ ] Add unit tests for new ViewModels covering import handling, settings server sorting/deletion, LibraryInfo loading text, support export state transitions, and shelf refresh/book-tap commands.
[ ] Run targeted ViewModel tests first, then full `xcodebuild test` on the iPhone 17 simulator.
[ ] Update `AGENTS.md` and memory-bank notes with the new main-view ViewModel boundaries after implementation.

## Validation Plan

- Build:
  - `xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Targeted tests:
  - New `MainViewModelTests`
  - New `SettingsViewModelTests`
  - New or expanded `LibraryInfoViewModelTests`
  - New `SupportInfoViewModelTests`
  - New shelf ViewModel tests if UIKit controllers are touched
- Full tests:
  - `xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData`

## Risks

- `MainView` owns cross-modal dismissal through `presentingStack`; moving it without tests can break import and reader presentation flows.
- Settings server replacement mutates servers, libraries, sync status, shelf state, and reachability probing. It should move as a single tested command, not as scattered helper rewrites.
- LibraryInfo already has multiple ViewModels. Adding another layer must clarify ownership rather than creating duplicate source of truth.
- Shelf controllers mix UIKit layout, ads, Combine subjects, and navigation. Refactor them incrementally and keep UI adapter behavior intact.
- Reader adapters still depend on `ModelData.shared`; defer them unless P1f acceptance explicitly includes reader internals.

## Acceptance Criteria

- Main user-facing screens no longer perform business workflow orchestration directly in SwiftUI body/helper methods.
- Remaining `ModelData` usage in main views is either dependency injection, simple environment forwarding, or explicitly documented composition-root access.
- New ViewModels are directly unit-testable without presenting SwiftUI/UIKit views.
- Existing BookDetail, Server detail, ReaderOptions, V2 search/category, and reader behavior continue to pass their existing tests.
- Full build and tests pass after implementation.

