# Active Context

## Current Focus

`codex/yabr-pdf-optimization`: fix YabrPDF single-page margin-crop viewport
placement (content right of center, top offset / drift after page turns).

## Current Branch Notes

- Viewport fix landed (uncommitted): `PDFPageViewportFitter` (pure, in
  `Views/PDFView/Managers/`) computes scale + per-axis page/view anchors inside
  the readable rect (`pdfView.bounds` minus safe area, so the top margin starts
  below the nav bar; text is top-aligned even when PDFKit would center a page
  shorter than the view). `YabrPDFView.applyViewport` drives the internal
  `UIScrollView` `contentOffset`, extending `contentInset` when the anchor is
  outside PDFKit's scrollable range. Fit and history-restore both use it; the
  bottom-right jump, `go(to:)` compensation passes, and DEBUG page annotations
  are gone. `marginOffset` moved from detection into the fitter.
- Tests: `YabrPDFMarginCropTests` (window-hosted, synthetic + generated
  book-like PDFs, real next/prev buttons) and `PDFPageViewportFitterTests`.
  Only the two PDFKit probe tests still use `XCTExpectFailure` (documenting
  `go(to:)` quirks the fix no longer relies on).
- Detection fix (`PDFMarginCropController.blankBorderWidth`): scans up to half
  the page (was a quarter; `whiteLines` keeps its quarter-page window so side
  sensitivity is unchanged), and on the line axis (top/bottom for `LtR_TtB`,
  right/left for `TtB_RtL`) walks outward over ink within ~1.5x the first
  inter-line gap, keeping short first lines and ascenders but not running
  heads. Vertical-text behavior is only covered by a solid-block test.
- Theme (uncommitted): iOS ignores `CALayer.compositingFilter` (verified with
  real `simctl io screenshot` captures; blend layers render opaque), so blend
  overlays are not an option. `PDFThemePalette` drives it: sepia/forest use a
  plain alpha overlay (`YabrPDFView.themeOverlayView`) solved so white maps
  exactly to the theme colour (black -> ~(34,23,0) / (0,27,7)); dark stays in
  `PDFPageWithBackground.draw`, now per-document via `PDFPageRenderTheme` on the
  document delegate (the global `static fillColor` is gone). `blankView` was
  replaced by `YabrPDFView.jumpMaskView`: an opaque snapshot of the target page at
  its final viewport, shown only for jumps (`markJumpTarget` ->
  `pendingJumpMaskPage`, consumed in single-page `handlePageChange`), never for
  next/prev. View order: document < jump mask < theme overlay < tap labels.
  Toggling dark re-attaches the document (`invalidateRenderedPages`): PDFKit's
  tile cache ignores both `annotationsChanged(on:)` and a scale round-trip, which
  left white tiles in dark and inverted tiles after leaving dark. Verify tile
  state only with real `simctl io screenshot` captures: `drawHierarchy`
  re-draws and does not show stale tiles.
- Flicker ("must never flicker"): verified with `xcrun simctl io booted
  recordVideo` + per-frame ffmpeg analysis (white/unthemed frames, A->B->A
  blips, text-ink drops); screenshots at 2-3 fps miss 1-2 frame flashes. Dark
  flashed white because PDFKit's per-page placeholder (`PDFPageLayer` >
  `backgroundLayer`: white + unthemed preview, drawn without our `draw`)
  shows before tiles render. Fixes: `YabrPDFView.invertsPagePlaceholders`
  (iOS 16 `PDFPageOverlayViewProvider` hook + KVO on the layer's
  contents/backgroundColor, iOS 15 best-effort via scroll KVO, untested);
  dark page turns freeze the current page first (`coverPageTurnIfNeeded`) since
  PDFKit's transition starts before `handlePageChange`; every dark page change
  is masked; a loading cover hides the first layout. Overriding
  `PDFPage.thumbnail` does not affect PDFKit's placeholder.
  `testDarkInvertsPDFKitPagePlaceholders` fails loudly if PDFKit renames layers.
- Persisted `pageOffsetX/Y` keep the visible upper-left semantics
  (`getPagePoint` now measures `convert(bounds, to: page)`).
  `rememberInPagePosition` is still never read by navigation code.
- On `main`, `ReadingPositionViewModelTests.testDetailViewModelReadSelectedFormatOpensReaderPresentation`
  already fails; commit `8437dcaf` on `codex/dsreader-advanced-qa-integration` fixes it.
- PR #88 (`codex/folio-reader-integration`) has been merged. Reader workspace,
  FolioReader integration, reader tab hot-mounting, and persistent active reader
  restore are archived in [Reader Modernization](history/reader-modernization.md).
- The manual sync metadata refresh cleanup from the same merged branch is
  archived in [Network, Search, And Cache Modernization](history/network-search-cache-modernization.md).
- Keep this file as a short handoff entrypoint. Add only current, unresolved, or
  high-risk context here; move completed project records into the matching
  history file before merge.
- If a task changes architecture, validation status, known risks, or handoff
  expectations, update this file or the relevant history file before finishing.

## History Index

- [Reader Modernization](history/reader-modernization.md): Readium,
  FolioReader, PDF reader, reading position, highlights, preferences, Book
  Detail reader work, and reader workspace/window modernization.
- [AppContainer And Concurrency Modernization](history/app-container-concurrency-modernization.md):
  AppContainer demotion, manager async streams, Combine removal, and concurrency
  hardening.
- [Shelf Modernization](history/shelf-modernization.md): Recent/Discover shelf
  UI, `YabrShelfDataModel`, shelf bootstrap, and shelf Swift Concurrency
  migration.
- [Realm Boundary Convergence](history/realm-boundary-convergence.md): Realm
  boundary shrinkage, repository ownership, mapper extraction, and persistence
  cleanup.
- [Network, Search, And Cache Modernization](history/network-search-cache-modernization.md):
  Calibre networking, unified search/category, cache behavior, downloads, and
  network tests.
- [ModelData Elimination](history/modeldata-elimination.md): ModelData
  reduction, AppContainer introduction, protocol migration, and final deletion.
- [Legacy Completed Tasks And Milestones](history/legacy-completed-milestones.md):
  Older completed checklists and cross-cutting historical context.
- [UI Test Modernization](history/ui-test-modernization.md): offline mock
  fixtures, Browse/search/category coverage, FolioReader flow, journey
  consolidation, and performance-plan results.

## Active Constraints

- Preserve user changes; do not revert unrelated dirty work.
- Do not introduce CocoaPods, Carthage, or workspace-level dependency changes.
  The project uses Swift Package Manager.
- Prefer repositories/services/managers over direct Realm or network work in
  SwiftUI views.
- Before any `xcodebuild test`, run:

```bash
xcrun simctl shutdown all
```

- Standard iOS Simulator build:

```bash
xcodebuild build -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -clonedSourcePackagesDirPath /tmp/YabrSourcePackages
```

## Current UI Test Note (2026-07-12)

- The offline UI suite currently contains five journeys and 11 named
  activities; full history and verification are archived in
  [UI Test Modernization](history/ui-test-modernization.md).
- Stable two-clone scheduling remains unresolved on Xcode 26.5/CoreSimulator.
  Use the dedicated performance scheme/plan for experiments and do not treat
  the accepted 180-second deviation as a guaranteed performance baseline.
