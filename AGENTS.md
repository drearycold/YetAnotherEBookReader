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

- App: iOS 15.5+ and macOS 12+ via Catalyst ebook reader.
- UI: SwiftUI for app structure/settings and UIKit for reader-heavy surfaces.
- Readers: Readium R2 for EPUB/PDF/CBZ, FolioReaderKit for legacy EPUB, custom
  PDFKit stack for YabrPDF. YabrPDF requires iOS 16 / Mac Catalyst 16 (native
  edit menus); `ReaderInfo` resolves it to Readium PDF on older systems via
  `ReaderType.resolved()`.
- Persistence: RealmSwift for metadata, shelves, annotations, reading positions,
  preferences, search/category cache, and activity logs.
- Networking: Calibre content server APIs through `CalibreServerService`,
  Kingfisher for authenticated images, GCDWebServer/Readium web server pieces for
  local reader assets.
- Dependencies: Swift Package Manager only, all remote packages (see "Swift
  Packages"). Do not add CocoaPods, Carthage, or a separate workspace to the
  repository; a local one for overriding a package stays outside it.

## Build And Test

Use the shared Xcode project and scheme:

```bash
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages build
```

For runtime behavior, repository logic, search, reader changes, or any non-trivial
Swift change, prefer tests. Before any `xcodebuild test`, shut down running
simulators so stale app/process state cannot affect the run:

```bash
xcrun simctl shutdown all
```

Then run the focused or full test command:

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
```

Mac Catalyst build command:

```bash
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader-Catalyst -destination 'platform=macOS,variant=Mac Catalyst' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages build
```

### CI

`.github/workflows/ci.yml` runs on pushes to `main`, pull requests, and by
hand, on `macos-26` with the Xcode the project is developed with
(`XCODE_VERSION`):

- **iOS unit tests:** `build-for-testing` then `test-without-building` of
  `YetAnotherEBookReaderTests` on the newest iPhone 17 simulator. The UI
  journeys (`YetAnotherEBookReaderUITests`) aren't run.
- **Calibre contract tests:** `CalibreServerContractTests` against a real
  `calibre-server` (version `CALIBRE_VERSION`, see below).
- **Mac Catalyst build** of `YetAnotherEBookReader-Catalyst`.
- **Detect changes** runs first. When everything a pull request or push
  changes is documentation (Markdown at the repository root, or anything under
  `.agents/`), the three jobs above are skipped, and GitHub reports a skipped
  job as passed. Anything else, or any doubt
  (`.github/scripts/changed-code.sh` failing or listing a partial set), runs
  them all.
- All three build with `-onlyUsePackageVersionsFromResolvedFile`, so a stale
  `Package.resolved` fails CI instead of resolving anew, and with
  `CODE_SIGNING_ALLOWED=NO`.
- On failure the raw logs and the `.xcresult` are uploaded as an artifact.

`main` is protected by the repository ruleset **Protect main** (Settings >
Rules):

- Changes reach `main` only through a pull request, merged with a merge
  commit or squashed (no rebase merges). No approval is required.
- The **iOS unit tests** and **Mac Catalyst build** checks must pass; the
  branch need not be up to date with `main`. **Calibre contract tests** isn't
  required yet.
- Force pushes and deleting `main` are blocked. Nobody can bypass the rules,
  admins included.
- A required check is matched by its job `name:`. Renaming that job, or adding
  one that should be required, means updating the ruleset as well, or every
  pull request waits for a check that never reports.
- Auto-merge is allowed (`gh pr merge --auto --merge` or `--squash`), and
  GitHub deletes a pull request's branch when it merges. A squashed branch
  isn't an ancestor of `main`, so `git branch -d` refuses it; check that the
  pull request merged from the branch's tip, then delete it with `-D`.

### Calibre Contract Tests

`CalibreServerContractTests` run the app's own `CalibreServerService` against a
real calibre-server, for what the hand-written mocks can't show: how calibre
stores, merges and refuses what the app sends. They skip unless
`TEST_RUNNER_YABR_CALIBRE_URL` is set.

`.github/scripts/calibre-contract-server.sh start DIR` seeds an empty `DIR`:
- a library named `Test Library 测试` (key `Test_Library_测试`) with one EPUB
  and an integer custom column `#read_progress`;
- users `contract-writer`, the read-only `contract-reader`, and
  `contract-restricted`, whose per-library restriction matches no book.

It starts the server on port 18080 with Digest authentication and prints the
variables to set. It uses calibre's command-line tools from
`/Applications/calibre.app` (override with `CALIBRE_BIN`). Only one calibre
program can run per user at a time, so stop any other calibre-server or the
calibre app first. To run them locally:

```bash
.github/scripts/calibre-contract-server.sh start /tmp/yabr-calibre
TEST_RUNNER_YABR_CALIBRE_URL=http://127.0.0.1:18080 TEST_RUNNER_YABR_CALIBRE_USER=contract-writer TEST_RUNNER_YABR_CALIBRE_PASSWORD=writer-pass TEST_RUNNER_YABR_CALIBRE_READONLY_USER=contract-reader TEST_RUNNER_YABR_CALIBRE_READONLY_PASSWORD=reader-pass TEST_RUNNER_YABR_CALIBRE_RESTRICTED_USER=contract-restricted TEST_RUNNER_YABR_CALIBRE_RESTRICTED_PASSWORD=restricted-pass xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages -only-testing:YetAnotherEBookReaderTests/CalibreServerContractTests
.github/scripts/calibre-contract-server.sh stop /tmp/yabr-calibre
```

A test marked `XCTExpectFailure(…, strict: true)` pins a known bug. Once the bug
is fixed it passes, which fails it: remove the marker with the fix.

What calibre 9.11 does, as the tests pin it:

- **Reading positions:** calibre stamps them with its own clock and drops the
  `epoch` the app sends, keeping one per user, device and format. Across
  devices, the newest epoch is the newest upload, not the newest read.
- **Highlights merge per `uuid`, bookmarks per `title`:** the newest
  `timestamp` wins, a removal is a newer copy marked `removed`, and an older
  copy doesn't bring it back. Two bookmarks with one title are one bookmark to
  calibre, so the app keeps a book's bookmark titles unique and merges by
  title (`BookmarkMerge`). Two devices syncing through calibre keep each
  bookmark, a retitle and a removal (`testTwoDevicesKeepEachBookmark`).
- **Read-only users** can still save positions and annotations, but a
  metadata change gets 403 ("does not have permission to make changes"), which
  the app reports as `.authFailed`.
- **Credentials calibre rejects** end as a cancelled request in the app (the
  task delegate stops answering the challenge). The probe reports it as
  "cancelled, server may require authentication".
- **Library sync** (`CalibreLibraryManager.syncLibrary`) lists no books, and
  uses the requests browsing makes (`getLibrarySummary`):
  - `ajax/search`, newest change first, for the book count and the newest
    book;
  - `ajax/books` for that book's `last_modified`, the generation of the search
    and category caches, and its `user_metadata`, which describes the custom
    columns. calibre sets every column on every book, valued or not
    (`Cache._get_metadata`), and one made with `calibredb add_custom_column`
    has `"display": {}`;
  - `ajax/categories`, then each category.

  `last_modified` carries microseconds and the server's offset after an edit;
  `parseLastModified` reads it.
- **A user with a per-library restriction:** `ajax/search` answers within the
  restriction, so the summary counts the books that user may see.
- **Deleted books** show per book: `ajax/books` answers null for a book calibre
  doesn't have, and for one a restricted user may not see.
  `BookRepository.persistMetadataEntries` reports it, and Settings lists it as
  unavailable on the server (`librarySyncStatus.del`, kept by
  `CalibreBookManager.recordMetadataAnswers` from shelf and Book Detail
  refreshes and from browsing). Nothing is deleted locally.
- **Categories are named in the server's language,** and searched by the
  field their URL names, hex-encoded (`/ajax/category/617574686f7273/…` is
  `authors`; `CalibreLibraryCategory.field`). The sync keeps each library's
  name-to-field map (`CalibreLibrary.categoryFields`), and a filter keyed by a
  category's name searches its field
  (`testACategoryFilterFindsTheCategorysBooks`).
- **Metadata:** book metadata (`ajax/books`, `get/json`) and `set_metadata`
  work.
- **Downloads:** `BookDownloadManager` saves the EPUB. calibre writes current
  metadata into the file it sends, so the size can differ from
  `format_metadata`.

Checked by hand, not pinned:

- **Reading positions need a user.** Anonymously, setting one fails inside
  calibre with HTTP 500 and `book-get-last-read-position` answers 404 ("login
  required for sync"); the positions in `book-get-annotations` stay empty.
- **Annotations are per user**, anonymous ones included. Uploading some
  highlights leaves the others.
- **A calibre server running in another language** (`CALIBRE_OVERRIDE_LANG=zh_CN`
  when starting the seed script) names Authors "作者", and `作者:"=…"` finds
  nothing, with HTTP 200. The filter test passes against it;
  `testTheCategoriesAreRead` expects the English name.
- **A request line over 8 KB** (`max_header_line_size`) gets 400: about 1,300
  five-digit ids in one `ajax/books` URL. The app asks for 200 books at a time
  (`CalibreServerService.booksMetadataBatchSize`).
- **The `cdb` interface refuses a user with a per-library restriction** with 403
  ("Cannot use the command-line db interface with a user who has per library
  restrictions"), so the library sync doesn't use it.
- **`--url-prefix`:** calibre answers both the prefixed and the bare paths, so
  `makeEndpointURL` dropping a server URL's path prefix only breaks behind a
  reverse proxy that forwards nothing but the prefix.

Not covered: DSReader Helper's `/dshelper/*` endpoints. The plugin
(`dsreader/DSReaderHelper`) is a calibre GUI plugin that starts its own server
from the calibre app, so testing it means running the calibre GUI, not
`calibre-server`.

### Swift Packages

Every dependency is a remote Swift package recorded in `Package.resolved`, which
is all CI builds. Three of them are ours or forks:

| Package | Repository | Follows |
|---|---|---|
| FolioReaderKit | `drearycold/FolioReaderKit` | branch `master` |
| Readium | `dsreader/readium-swift-toolkit` | branch `feature/additional-safe-area-insets` |
| SwiftUICharts | `willdale/SwiftUICharts` | 2.10.4, up to next major |

- FolioReaderKit stays an independent library. `master` is its stable branch:
  changes reach it only through pull requests whose CI passed (its ROADMAP.md,
  "Branches and working rules"), so following `master` is safe, and the app
  takes a new commit only when `Package.resolved` is updated here.
- The Readium fork is 3.8.0 plus a margin-swipe fix that upstream has only in
  4.0.0-alpha (readium/swift-toolkit#872). Move to upstream 4.0 once it is
  released and drop the fork.
- To take a newer commit of a package that follows a branch, merge it into that
  branch, then update the package in Xcode (File > Packages > Update to Latest
  Package Versions), or delete its entry from `Package.resolved` and run
  `xcodebuild -resolvePackageDependencies -scmProvider system`. Check that no
  other entry in `Package.resolved` moved (a changed package can re-resolve its
  dependencies to newer versions), and commit it with the app change that needs
  it.

To build the app against a local FolioReaderKit checkout (or worktree) before
its changes are pushed, open both in a workspace kept outside the repository. A
local package overrides the remote one with the same name:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Workspace version = "1.0">
   <FileRef location = "absolute:/path/to/YetAnotherEBookReader/YetAnotherEBookReader.xcodeproj"></FileRef>
   <FileRef location = "absolute:/path/to/FolioReaderKit"></FileRef>
</Workspace>
```

Save it as `YabrDev.xcworkspace/contents.xcworkspacedata`, copy
`Package.resolved` into `YabrDev.xcworkspace/xcshareddata/swiftpm/` so the other
packages keep their versions, and build with `xcodebuild -workspace
YabrDev.xcworkspace -scheme YetAnotherEBookReader …`.

### Simulator Set

Keep one iPhone and one iPad per major iOS version; do not create extra device
models. Look UDIDs up with `xcrun simctl list devices available` rather than
hard-coding them.

| iOS | iPhone | iPad |
|---|---|---|
| 15.5 | iPhone 7 | none |
| 17.5 | none | iPad Pro (10.5-inch) |
| 18.5 | iPhone 16 | iPad mini (A17 Pro) |
| 26.5 | iPhone 17 | iPad mini (A17 Pro) |

- `name=iPhone 17` in the commands above resolves to the iOS 26.5 device. For
  iOS 18 runs pass `platform=iOS Simulator,id=<iPhone 16 UDID>`, and for iOS 15
  runs `id=<iPhone 7 UDID>`.
- iOS 15.5 is the deployment target, so the iPhone 7 is the oldest system the
  app runs on. Run it for SwiftUI navigation or presentation changes: iOS 15
  differs there (`NavigationLink(isActive:)`, one toolbar item per placement).
- When a simulator runtime is removed in Xcode, its devices stay on disk as
  `unavailable`. Clear them with `xcrun simctl delete unavailable`.
- If a delete fails with "Operation not permitted", QuickLook thumbnails under
  `data/.DocumentRevisions-V100` are read-only directories. Run
  `chmod -R u+w <device dir>` on the device directory, then delete it again.

If a full test run is too expensive for the change, run the narrowest relevant
test target or class first, then state exactly what was and was not verified.

## Architecture Map

### Entry And App State

- `YetAnotherEBookReader/YetAnotherEBookReaderApp.swift` creates the global
  `AppContainer`, initializes Realm on scene activation, and injects shared
  environment objects.
- `YetAnotherEBookReader/MainView.swift` owns the main tab shell:
  - `RecentShelfView`
  - `SectionShelfView`
  - `LibraryInfoView`
  - `SettingsView`
- `YetAnotherEBookReader/Models/App/AppContainer.swift` is the composition root
  (it replaced the deleted `ModelData.swift`). It owns every repository,
  manager, service, and runtime state, and conforms to `AppContainerProtocol`,
  `LibraryProvider`, and (transitively) `LibraryResolver` / `ServerResolver`.
  `YetAnotherEBookReaderApp` creates a single `AppContainer()` as `@StateObject`
  and injects it via `.environmentObject(container)`.

### Managers

Use managers for app-domain coordination. Keep new business logic out of
`AppContainer`, the composition root.

- `CalibreServerManager`: server list, credentials, reachability probes,
  DSReader Helper configuration.
- `CalibreLibraryManager`: library list, local library bootstrapping, library
  probing, and the library sync: its summary (book count, newest change,
  custom columns) and categories, never a book list. Books are fetched as
  they're browsed or shelved (`LibrarySearchService`,
  `CalibreBookManager.getBooksMetadata`).
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
  `Models/Calibre/`, `Models/Domain/`, `Models/Utils/`, and `Network/`. The
  decomposition is a zero-behavior move:
  - `Calibre/CalibreCoreModels.swift`: `CalibreServer`, `CalibreLibrary`,
    `CalibreBook`, `CalibreSyncStatus`.
  - `Domain/ReadingPositionModels.swift`: `BookDeviceReadingPosition`,
    `BookDeviceReadingPositionHistory`, reading statistics.
  - `Calibre/CalibreHighlightStyle.swift`: `BookHighlightStyle` (only model
    file in the split that imports UIKit).
  - `Calibre/CalibreTasks.swift`: network/metadata task structs
    (`CalibreBookTask`, `CalibreBooksMetadataRequest`, `CalibreBooksTask`,
    `CalibreLibraryProbeTask`, `CalibreLibrarySearchTask`,
    `CalibreBookSetLastReadPositionTask`, `CalibreBookUpdateAnnotationsTask`).
  - `Calibre/CalibrePayloadModels.swift`: Codable API entry/result payloads
    (`CalibreBookEntry`, `CalibreBookLastReadPositionEntry`,
    `CalibreBookAnnotationsResult`, `CalibreBookAnnotationsMap`,
    `CalibreLibraryBooksResult`, etc.).
  - `Calibre/CalibreSyncModels.swift`: custom columns, category keys, probe/sync
    requests, `CalibreLibrarySummary`.
  - `Calibre/CalibrePluginModels.swift`: DSReader Helper / Count Pages /
    Goodreads Sync preferences and `CalibreDSReaderHelperConfiguration`.
  - `Network/CalibreActivityModels.swift`: `CalibreActivity`/`Start`/`Finish`.
  - `Utils/Array+Chunks.swift`: generic `Array.chunks(size:)` helper.
- `Models/Realm/*`: Realm object schema and Realm/domain mappers. Treat edits
  here as migration work. `CalibreSearchCache.swift` now lives here.
- `Domain/YabrData.swift`: format, reader, reader-info, and app-specific value
  types.
- `Domain/BookFiles.swift`: import and local-file helpers.
- `Domain/BookPreference.swift`, `Domain/BookBookmark.swift`,
  `Domain/BookHighlight.swift`: reader preferences and annotation value types.

### Search And Category

The modern path is value-type/actor based. Do not revive direct
`CalibreUnifiedSearchObject` bindings in views.

- `AppContainer` owns the V2 root dependencies directly:
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
- `CalibreBrowser.swift` / `CalibreLibrarySearchManager` are historical only;
  treat older analysis that references them as pre-P1e context rather than live
  architecture.

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
- `Views/ShelfView/*`: native SwiftUI Recent/Discover shelves (`RecentShelfView`, `SectionShelfView`, view models, and components). The shelf data model (`YabrShelfDataModel`) lives in `Models/Managers/ShelfDataManager.swift` (moved out of `Views/ShelfView/` in Milestone P2/A10).
- `Views/DictView/*`: dictionary and external lookup UI.

## Coding Rules

- Keep changes scoped to the feature or bug. Avoid opportunistic rewrites.
- Prefer existing patterns and local helpers over new abstractions.
- New complex SwiftUI views should use dedicated ViewModels instead of putting
  networking, Realm queries, or mutation logic in the view.
- Preserve the `AppContainer` composition root for new callers, but place
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
  `AppContainer.tryInitializeDatabase(statusHandler:)`.

### Verification Checklist

Before finalizing any changes to persistence, check that none of the following patterns are introduced:
- Direct `RealmSwift` imports in views:
  `rg "import RealmSwift" YetAnotherEBookReader/Views/`
- Direct `CalibreBook(managedObject:)` or `BookDeviceReadingPosition(managedObject:)` usage outside approved mapper or repository files.
- `realm.create(... value: [String: Any])` outside repository/cache sync paths.

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

A library's search status (`LibrarySearchStatus`) says whether it is loading
or failed; the UI reads loading from it, not from the merge offsets. A library
whose search fails shows what its search cache has, from any of its server's
URLs (`UnifiedSearchService.cachedResult`), and the cache is shown before the
server answers.

### Book Detail

Start with `BookDetailViewModel` and `BookDetailSubviews`. Avoid reintroducing
direct `AppContainer` or Realm dependencies into `BookDetailView` subviews.

Any screen that can open a reader is pushed, never presented in a sheet. The
reader workspace is an overlay in `MainView` (a `ZStack` over the tabs), and a
sheet is a UIKit modal above it, so a reader opened from a sheet appears behind
it. Book Detail and Reading History are pushed:
- **Recent and Discover:** one hidden `NavigationLink(isActive:)` on the
  shelf's root, driven by the view model (`RecentShelfRoute`,
  `presentingBookDetailId`).
- **Book Detail to Reading History:** a hidden link driven by
  `isReadingPositionHistoryActive`.
- **Reading History to a position:** a hidden link driven by `detailPosition`.
  Its rows are sibling buttons (details, and ▶ to continue reading), not
  NavigationLinks. A button inside a NavigationLink row pushes the row instead
  of running its own action.

Opening a reader into a workspace also publishes `publishDismissAll`, so a sheet
or popover that can stay up while a reader opens should close on
`dismissAllEvents()` (as `LibraryInfoView` and `ReaderOptionsViewModel` do).

Readers opened from these screens pass `@Environment(\.readerWorkspaceID)` as
the `targetWorkspaceID`. Opening a reader at a saved position goes through
`ReadingPositionListViewModel.continueReading(at:format:readerType:targetWorkspaceID:)`.

### Reader Behavior

Start with `ReadingSessionManager`, `ReaderEngineProtocol`,
`YabrEBookReader.swift`, and the specific engine implementation. Any progress,
highlight, or preference change must be checked across YabrPDF, Readium, and
FolioReader paths when the behavior is shared.

### PDF Reader

`YabrPDFViewController` is a coordinator. It hosts its page view in a
`PDFReaderSurface`, which owns what page views share:
- the theme overlay, jump mask and loading cover;
- the page-turn tap zones and the app's taps, plus the highlight edit menu;
- the highlight annotations.

It also keeps the neighbour pages rendered in buffer page views (#54/#55). A
page turn onto a rendered buffer makes that buffer the active page view, so the
active view changes. Read `pdfView` (the active page view) at the point of use,
never store it, and observe the surface's notifications. Keep specialized behavior in the existing managers/extensions:

- `PDFAnnotationManager`
- `PDFBookmarkManager`
- `PDFSearchController`
- `PDFMarginCropController`
- `PDFColumnDetector` and `PDFReadingFlow` (reading regions and steps, #97/#19);
  jumps go through `YabrPDFViewController.jump(to:)` so they land on the step
  showing their destination
- `YabrPDFViewController+Chrome`
- `YabrPDFViewController+Navigation`
- `YabrPDFViewController+Options`
- `YabrPDFViewController+Selection`
- `YabrPDFViewController+Sharing`
- `YabrPDFViewController+ReadingFlow`

Avoid growing the main controller again.

## Current Handoff Context

The main workstream is still reader architecture modernization and large-file
decomposition. The ModelData god-object elimination plan (Phases 0-4) is now
**complete**; `ModelData.swift` and the `CalibreServerConfigProvider` protocol
have been deleted and replaced by `AppContainer` + `AppContainerProtocol`.

- **Phase 4: ModelData Elimination (2026-06-25, complete):** `ModelData.swift` (was 1,073 lines) and `CalibreServerConfigProvider.swift` (24 lines) are fully deleted. The replacement is a 366-line `Models/App/AppContainer.swift` (composition root) + 130-line `Models/App/AppContainerProtocol.swift` (facade aggregating all repos / managers / services / subjects / runtime state). The four sub-phases:
  - **4a+4b (commit 5f28bc9):** Created `AppContainer` as a verbatim mirror of `ModelData`; widened 11 manager / repository / init-helper `init` and `weak var` types from `ModelData` to `AppContainerProtocol`; extended `AppContainerProtocol` with the missing runtime state (`calibreLibraries`, `calibreServers`, `librarySyncStatus`, `deviceName`, etc.), sync progress (`updatingMetadata*`), database lifecycle, activity log, and `LibraryResolver` / `ServerResolver` conformances. Converted the three `ModelData` extensions in `ShelfDataManager.swift` to extensions on `AppContainerProtocol where Self: ObservableObject`. Both classes compiled and 329 tests passed.
  - **4c (commit 23708d1):** Bulk-renamed `ModelData` → `AppContainer` and `modelData` → `container` across 36 app source files and 6 test files. The 11 init/setup parameter labels were updated to `container:` to match. `YetAnotherEBookReaderApp` now creates `AppContainer()` as the sole `@StateObject`. All 16 View files declare `@EnvironmentObject var container: AppContainer`. All 9 ViewModels + the `YabrEBookReaderNavigationController`, `EpubFolioReaderContainer`, and `FolioReaderViewController` adapters take `container: AppContainer`. 6 `ModelData.shared` access sites switched to `AppContainer.shared`. 329 tests pass.
  - **4d (commit 0e2fa0e):** Deleted `Models/ModelData.swift` (382 lines) and `Models/CalibreServerConfigProvider.swift` (24 lines). `CalibreServerService` now takes `AppContainerProtocol` instead of `CalibreServerConfigProvider`. `AppContainerProtocol` absorbed `updateBook` / `getPreferredFormat` from the deleted protocol. Xcode project updated. 329 tests pass. The full Phase 4 is complete: ModelData 1,073 → 0 lines, replaced by 366-line AppContainer + 130-line AppContainerProtocol.
- **Test Coverage Expansion - Phase 1d: Mock Infrastructure (2026-06-23):** Centralized mock infrastructure under a new navigator group and directory `YetAnotherEBookReaderTests/TestHelpers/`. Created reusable doubles for repositories (`MockServerRepository`, `MockLibraryRepository`, `MockBookRepository`, `MockReadingPositionRepository`, `MockAnnotationRepository`), managers (`MockServerManager`, `MockLibraryManager`, `MockBookManager`), in-memory Realm DB bootstrappers (`MockDatabaseService`), and a factory builder for domain types (`TestFixtures`). Centralized `MockURLProtocol` into `TestHelpers/` and removed its duplicate inline definition in `UnifiedSearchIntegrationTests.swift`. All 227 unit tests pass, and Catalyst build succeeds.
- **Test Coverage Expansion - Phase 1c: CalibreServerManagerTests (2026-06-23):** Implemented `CalibreServerManagerTests.swift` covering `CalibreServerManager` server CRUD, reachability status helpers, DSReaderHelper config updates, background probing, and library auto-creation flows. Fixed an in-memory dictionary cache leak in `CalibreLibraryManager.removeLibrary(library:)` where deleted libraries were not cleaned up from the active in-memory `calibreLibraries` cache. All 9 focused test cases pass, and the unit test suite passes with 227 tests.
- **Test Coverage Expansion - Phase 1b: CalibreLibraryManagerTests (2026-06-23):** Implemented `CalibreLibraryManagerTests.swift` covering `CalibreLibraryManager` library CRUD, visibility toggling (hide/restore), server metadata updates, probing, removed cache clearing, probe-based last-modified sync, and full Calibre server category/book syncing. Configured custom mock calibre servers to support realistic test execution against `MockURLProtocol` interceptors. All 11 focused test cases pass, and the full test suite passes with 218 tests.
- **P2/A26 Readium Volume Key Timing Modernization (Milestone A26):** Modernized the volume key paging timing and event interpretation architecture in Readium view controllers, completely removing wall-clock delays (`DispatchQueue.main.asyncAfter`) and polling loops:
  - Extracted a pure event resolver `ReadiumVolumeKeyEventResolver` and state coordinator `ReadiumVolumeKeyPagingCoordinator` under `Views/ReadiumView/` to interpret raw volume changes (up/down/busy/programmatic) thread-safely.
  - Replaced the recursive `setSystemVolume` timer loop in `YabrReadiumReaderViewController.swift` with layout-driven `UISlider` discovery using a static tree-search helper `findVolumeSlider(in:)` invoked in `viewDidLayoutSubviews()`.
  - Replaced the 0.1-second event unlock delay with completion-based async boundaries: introduced `performVolumeKeyPage(up:) async` and awaited page navigation / vertical scroll animations (using a safe non-blocking offset polling loop with a 0.4s timeout) before resetting and unlocking.
  - Hardened lifecycle de-activation, settings toggles, and added idempotency guards.
  - Added comprehensive test coverage in `ReadiumVolumeKeyPagingCoordinatorTests.swift` covering resolver, coordinator, and slider discovery. All 180 unit tests pass.
- **P2/A27 Realm Value Conversion Modernization (Milestone A27):** Modernized the persistence mapping layer to prevent boilerplate duplication, thread boundary leaks, and field drift risks:
  - Created dedicated explicit mapping files `CalibreRealmMappers.swift`, `ReadingPositionRealmMappers.swift`, and `AnnotationRealmMappers.swift` under `Models/Realm/`.
  - Refactored repositories (`RealmServerRepository`, `RealmLibraryRepository`, `RealmBookRepository`, `RealmAnnotationRepository`, and `RealmReadingPositionRepository`) to use the explicit mappers.
  - Eliminated duplicate conversion shims outside the persistence boundary in `LibrarySearchService`, `RealmSearchCacheStore`, `CalibreBookManager`, `ReadingSessionManager`, and `ReadingPositionViewModel`.
  - Standardized write-side population by implementing in-place `applyDomain` updates on all 7 Realm models, guarding identity properties/primary keys against modification on managed objects.
  - Introduced a generic `replaceAll` extension on Realm `List` to cleanly update nested collections in-place.
  - Refactored `RealmAnnotationRepository.saveBookmark` to perform in-place updates on existing managed bookmarks.
  - Cleaned up Calibre sync payload boundary by deleting unused legacy payload converter extensions on `BookHighlightRealm` and `BookBookmarkRealm`.
  - Added a golden test suite `RealmDomainMappingTests` verifying all round-trip and update semantics.
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

Recorded result (2026-10-12): 853 unit tests passed, 1 skipped (the opt-in
margin-detection benchmark). The Recent and Browse detail UI journeys pass on
the iPhone 17 (iOS 26.5) and the iPhone 7 (iOS 15.5). The Mac
Catalyst build succeeds; the old SPM product resolution failure (`R2Navigator`,
`GCDWebServer`, `R2Shared`, `R2Streamer`) no longer reproduces.

## Known Risks

- The managers and `CalibreServerService` reach the rest of the app through
  `AppContainerProtocol`. Small changes to it or to `AppContainer` can have
  large effects.
- Reader progress saving spans multiple engines. Verify shared reader behavior
  in all relevant reader paths.
- Realm threading mistakes usually appear only under background sync, search,
  shelf updates, or test concurrency.
- `CalibreServerService` caches a `URLSession` per server address, username and
  password. A newer password retires the older one's sessions. A retired session
  is invalidated once its last `withURLSession` request ends, and creating a task
  in an invalidated session crashes. Make requests through `validatedData` or
  `withURLSession`, not a session kept from `urlSession(server:)`.
- Search/category code has both legacy coordinator pieces and modern actor/value
  services. Prefer the modern services for new behavior.
- Xcode project file drift is easy when adding Swift files. Confirm target
  membership through build/test.
