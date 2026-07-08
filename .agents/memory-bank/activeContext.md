# Active Context

## Current Focus
The current branch is `codex/folio-reader-integration`. Active work is focused
on reader architecture modernization: multiple reader presentations, reader
workspace tabs, and iPad/Mac window scene support.

Keep this file focused on the active branch and the few current project notes a future agent needs by default. Full historical records live under `.agents/memory-bank/history/`.

## Current Branch Projects
Uncommitted reader preference compatibility work is present in the working tree:
`ReaderEnginePreferences.themeMode` now uses canonical shared theme values, and
`ReaderPreferenceRepository.loadInitialPreferences` falls back across compatible
reader engines when the target engine has no saved preferences for the book.
FolioReader now also has full native per-book preference persistence so
Folio-only settings are not lost through the cross-engine compatibility layer.

Reader presentation has moved off the old single global reader state. The branch
adds `ReaderPresentation` snapshots to `ReadingSessionManager`, routes
shelf/detail/import/reading-position open actions through `openReader(...)`,
removes the `AppContainer.presentingStack` dismiss workaround, and binds
FolioReader providers to the concrete reader instance's book/readerInfo instead
of `bookManager.readingBook` / `sessionManager.readerInfo`. Validation completed
for this slice:

```bash
git diff --check
xcrun simctl shutdown all
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages -only-testing:YetAnotherEBookReaderTests/ReadingSessionManagerTests -only-testing:YetAnotherEBookReaderTests/MainViewModelTests -only-testing:YetAnotherEBookReaderTests/BookDetailViewModelTests -only-testing:YetAnotherEBookReaderTests/RecentShelfViewModelTests -only-testing:YetAnotherEBookReaderTests/FolioReaderProviderBookIdTests
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
```

Recorded result: `git diff --check` passed, 71 focused tests passed, and the
iOS Simulator build succeeded. Follow-up risk: the compatibility
`readingBook`/`readerInfo`/`presentingEBookReaderFromShelf` accessors still exist
inside the manager layer for older tests/callers and can be removed in a later
cleanup once remaining manager-level references are migrated.

Review follow-up completed: `ReaderWorkspaceView` now keys `YabrEBookReader` by
`ReaderPresentation.id` so activating another reader presentation rebuilds the
underlying UIKit reader instead of reusing the old representable controller.
Validation rerun after the fix: `git diff --check`, the same 71 focused reader
tests, and the standard iOS Simulator build all passed.

Reader workspace/window scene upgrade is implemented in the current working
tree. `MainView` now hosts a persistent reader workspace overlay with tabs
instead of a single full-screen cover; hiding the reader keeps mounted tabs
alive. `ReaderWorkspaceViewModel` owns per-scene reader tab membership,
activation, close, hide/show, and "open active reader in a new window" behavior.
`YetAnotherEBookReaderApp` now creates one `MainViewModel` per scene and handles
reader scene restoration through `NSUserActivity`. `AppContainer` owns reader
open requests, active reader workspace routing, scene activity helpers, and the
app-wide probe timer tied to active app scenes. The old app-wide
`bookReaderActivity` async bridge was removed; reader lifecycle events now flow
from each workspace to its hosted reader controllers.

Validation completed for the workspace/window scene slice:

```bash
git diff --check
xcrun simctl shutdown all
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages -only-testing:YetAnotherEBookReaderTests/ReadingSessionManagerTests -only-testing:YetAnotherEBookReaderTests/MainViewModelTests -only-testing:YetAnotherEBookReaderTests/BookDetailViewModelTests -only-testing:YetAnotherEBookReaderTests/RecentShelfViewModelTests -only-testing:YetAnotherEBookReaderTests/FolioReaderProviderBookIdTests
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
```

Recorded result: `git diff --check` passed, 73 focused tests passed, and the
iOS Simulator build succeeded. Follow-up risk: inactive reader tabs remain
mounted so state is preserved, but reader analytics/lifecycle semantics are still
scene-wide rather than "visible tab only." The compatibility
`activeReaderPresentation` / `readingBook` / `readerInfo` accessors still exist
for older callers and tests and can be removed in a later cleanup.

Reader workspace top-obstruction follow-up completed: the workspace now measures
the floating tab toolbar height and applies a matching top inset to the hosted
reader content/fallback view, so the toolbar no longer covers the first lines of
reader text. The workspace uses the underlying `YabrEBookReaderRepresentable`
inside this inset container so the legacy `YabrEBookReader.ignoresSafeArea()`
wrapper remains unchanged for other call sites. Validation:

```bash
git diff --check
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
xcrun simctl shutdown all
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages -only-testing:YetAnotherEBookReaderTests/MainViewModelTests -only-testing:YetAnotherEBookReaderTests/ReadingSessionManagerTests -only-testing:YetAnotherEBookReaderTests/BookDetailViewModelTests -only-testing:YetAnotherEBookReaderTests/RecentShelfViewModelTests
```

Recorded result: `git diff --check` passed, the iOS Simulator build succeeded,
and 48 focused tests passed.

Reader workspace hide-button follow-up completed: the left toolbar button was
calling `ReaderWorkspaceViewModel.hideReader()`, but the outer `MainView` owned
the overlay opacity/hit-testing modifiers while only `ReaderWorkspaceView`
observed the nested workspace object. The overlay now keeps those modifiers
inside `ReaderWorkspaceView`, so `isPresented` changes redraw the same view that
handles the button. Validation:

```bash
git diff --check
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
xcrun simctl shutdown all
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages -only-testing:YetAnotherEBookReaderTests/MainViewModelTests
```

Recorded result: `git diff --check` passed, the iOS Simulator build succeeded,
and 11 `MainViewModelTests` passed.

Reader workspace duplicate-tab follow-up completed: reopening the same book from
Recent Shelf now reuses the existing `ReaderPresentation` when the book,
format, and reader type match, so the workspace activates the existing tab
instead of appending another identical tab. `AppContainer.openReader` and
`ReadingSessionManager.openReader` keep `reuseExisting` enabled by default;
`ReaderWorkspaceViewModel.openActivePresentationInNewWindow()` passes
`reuseExisting: false` so the explicit new-window action can still create a
separate same-book presentation. Validation:

```bash
git diff --check
xcrun simctl shutdown all
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages -only-testing:YetAnotherEBookReaderTests/ReadingSessionManagerTests -only-testing:YetAnotherEBookReaderTests/MainViewModelTests
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
```

Recorded result: `git diff --check` passed, 22 focused tests passed, and the
iOS Simulator build succeeded.

Reader workspace iPhone toolbar follow-up completed: `ReaderWorkspaceView` now
places the floating reader tab toolbar at the bottom on iPhone while keeping the
top toolbar on iPad and Mac Catalyst. Reader content applies the measured
toolbar inset on the active edge, and the "open in new window" button is hidden
when the current platform does not support reader windows. `AppContainer`
centralizes the reader-window support check, and `ReaderWorkspaceViewModel`
no-ops the new-window action on unsupported platforms so iPhone no longer
creates a duplicate reader presentation. Validation:

```bash
git diff --check
xcrun simctl shutdown all
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages -only-testing:YetAnotherEBookReaderTests/MainViewModelTests -only-testing:YetAnotherEBookReaderTests/ReadingSessionManagerTests -only-testing:YetAnotherEBookReaderTests/BookDetailViewModelTests -only-testing:YetAnotherEBookReaderTests/RecentShelfViewModelTests
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
```

Recorded result: `git diff --check` passed, 52 focused tests passed, and the
standard iOS Simulator build succeeded. Manual iPhone/iPad reader toolbar
verification is still recommended because this is a visual placement change.

FolioReader zero-margin follow-up completed: the residual top/bottom whitespace
was rooted in FolioReaderKit reserving safe-area/status-bar height and page
indicator height inside `FolioReaderPage.webViewFrame()`/`anchorBoundsFrame()`,
plus bundled CSS forcing `@page` top/bottom margins. FolioReaderKit now has
compatibility-default config switches for those reserved page-frame components,
DSReader disables both for FolioReader containers so the workspace chrome
remains the only top inset, and bundled CSS no longer injects nonzero `@page`
top/bottom margins. Validation:

```bash
git diff --check
git -C /Users/peterlee/git/FolioReaderKit diff --check
xcrun simctl shutdown all
xcodebuild test -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages -only-testing:YetAnotherEBookReaderTests/FolioReaderProviderBookIdTests -only-testing:YetAnotherEBookReaderTests/ReadingSessionManagerTests
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
```

Recorded result: both diff checks passed, FolioReaderKit ran 71 tests with 0
failures, DSReader focused tests ran 35 tests with 0 failures, and the standard
iOS Simulator build succeeded. Manual iPhone/iPad margin verification is still
recommended because this change targets visual reader layout.

FolioReader internal close-button follow-up completed: the redundant close
button came from FolioReaderKit always inserting `closeReader(_:)` into the
left navigation bar buttons. FolioReaderKit now exposes compatibility-default
`FolioReaderConfig.showCloseButton`, and DSReader's Folio configuration sets it
to `false` because reader close/tab management is owned by the workspace chrome.
Validation:

```bash
git diff --check
git -C /Users/peterlee/git/FolioReaderKit diff --check
xcrun simctl shutdown all
xcodebuild test -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FolioReaderKitTests/FolioReaderConfigTests -only-testing:FolioReaderKitTests/NavigationBarVisibilityTests
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages -only-testing:YetAnotherEBookReaderTests/FolioReaderProviderBookIdTests
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
```

Recorded result: both diff checks passed, FolioReaderKit focused tests ran 11
tests with 0 failures, DSReader focused tests ran 26 tests with 0 failures, and
the standard iOS Simulator build succeeded. The DSReader focused test command
also printed the known post-suite `Missing AppContainer environment` fatal after
success; xcodebuild still returned success. Manual FolioReader visual
verification is still recommended for the actual nav-bar appearance.

FolioReader iPadOS menu tab placement follow-up completed: iPadOS 18+ can
promote `UITabBarController` tabs away from the old bottom placement, which made
FolioReader's Page/Font/Paragraph/Advanced/Profile settings tabs appear at the
top on newer iPads. FolioReaderKit now exposes compatibility-default
`FolioReaderConfig.forceBottomMenuTabBar`; `FolioReaderCenter` applies `.tabBar`
mode on iOS 18+ and, when the flag is enabled, applies a compact horizontal
trait override only to the settings menu controller. DSReader enables the flag
for Folio containers. Validation:

```bash
git diff --check
git -C /Users/peterlee/git/FolioReaderKit diff --check
xcrun simctl shutdown all
xcodebuild test -scheme FolioReaderKit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FolioReaderKitTests/FolioReaderConfigTests -only-testing:FolioReaderKitTests/NavigationBarVisibilityTests
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -clonedSourcePackagesDirPath /tmp/YabrSourcePackages -only-testing:YetAnotherEBookReaderTests/FolioReaderProviderBookIdTests
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
```

Recorded result: both diff checks passed, FolioReaderKit focused tests ran 13
tests with 0 failures, DSReader focused tests ran 27 tests with 0 failures, and
the standard iOS Simulator build succeeded. The first sandboxed build attempt
failed because SwiftPM/clang cache writes outside the workspace were blocked;
the approved non-sandbox `xcodebuild` rerun succeeded. Manual iPadOS visual
verification is still recommended for the actual menu tab placement.

Completed `fix/library-book-list` work was archived into [Network, Search, And Cache Modernization](history/network-search-cache-modernization.md) under **fix/library-book-list Branch Archive (2026-07-05, complete)**.

## Pre-Merge Archive Rule
- Before merging a branch, archive completed branch work from `Current Branch Projects` into the matching `.agents/memory-bank/history/` project file.
- Keep `activeContext.md` as a short entrypoint: current focus, active branch projects, constraints, and links to history.
- Prefer project boundaries over dates or arbitrary entry counts when moving records.

## History Index
- [Realm Boundary Convergence](history/realm-boundary-convergence.md): Realm boundary shrinkage, repository ownership, mapper extraction, and persistence cleanup.
- [AppContainer And Concurrency Modernization](history/app-container-concurrency-modernization.md): AppContainer demotion, manager async streams, Combine removal, and concurrency hardening.
- [Shelf Modernization](history/shelf-modernization.md): Recent/Discover shelf UI, YabrShelfDataModel, shelf bootstrap, and shelf Swift Concurrency migration.
- [ModelData Elimination](history/modeldata-elimination.md): ModelData reduction, AppContainer introduction, protocol migration, and final deletion.
- [Reader Modernization](history/reader-modernization.md): Readium, FolioReader, PDF reader, reading position, highlights, preferences, and Book Detail reader work.
- [Network, Search, And Cache Modernization](history/network-search-cache-modernization.md): Calibre networking, unified search/category, cache behavior, downloads, and network tests.
- [Legacy Completed Tasks And Milestones](history/legacy-completed-milestones.md): Old completed checklists and cross-cutting historical context.

## Active Constraints
- **Do NOT** introduce CocoaPods or modify workspace files; the project relies entirely on Swift Package Manager.
- **Decoupling Goal:** Views should minimize direct dependency on `ModelData` for network operations; logic should reside in dedicated ViewModels.
- **Validation Workflow:** Before any `xcodebuild test`, shut down running simulators with `xcrun simctl shutdown all`. Add `-clonedSourcePackagesDirPath /tmp/YabrSourcePackages` to `xcodebuild` build/test commands to reuse SPM checkouts. After validation passes, start one Debug run through the Xcode MCP integration when that tool is available.
