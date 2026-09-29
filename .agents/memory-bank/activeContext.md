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
- YabrPDF requires iOS 16 / Mac Catalyst 16 (uncommitted): `ReaderType.resolved()`
  maps YabrPDF to ReadiumPDF on older systems and `ReaderInfo.init` applies it,
  so every launch path falls back; YabrPDF types are `@available(iOS 16.0,
  macCatalyst 16.0, *)`. Menus are native (`Managers/PDFMenuManager.swift`,
  modelled on FolioReaderKit's `WebViewMenuManager`): selection actions are
  injected by `YabrPDFView.buildMenu(with:)`; tapping a highlight shows the
  app's own `UIEditMenuInteraction` (Copy / Select / Style ▸ / Delete). PDFKit
  has its own markup menu for highlight taps (Copy / Highlight / Remove / Add
  Note) that bypasses the app's persistence and does not go through
  `buildMenu`; `highlightMenuTapGestureRecognizer` only begins on a highlight
  and PDFKit's taps are required to wait for it. PDFView declares but does not
  implement `gestureRecognizer(_:shouldBeRequiredToFailBy:)` — never call
  super there. MenuItemKit / UIMenuController / `YabrPDFAnnotationView` are gone
  from YabrPDF (FolioReaderKit still uses MenuItemKit on iOS 15).
- PDFKit differs between iOS 18.5 and 26.5; run the PDF suites (and, for
  flicker, a `recordVideo` session) on both. iOS 18 leaves `PDFPageLayer`'s
  sublayers unnamed, so the placeholder is matched as `backgroundLayer` or the
  unnamed child at z = -900. iOS 18 centres a document smaller than the view by
  moving `PDFDocumentView` during layout, cancelling scroll offsets; the fit pads
  `pageBreakMargins` (single-page only, followed by `layoutDocumentView()`) so
  the document always covers the view, and continuous mode restores PDFKit's
  default margins via `restoreDefaultPageBreakMargins()`.
  The iOS 18 edit menu expands the highlight Style submenu inline and
  horizontally, without the swatch images or the ✓ on the current style that
  iOS 26 shows; both behave the same otherwise (verified by hand on 18.5/26.5).
- Highlight notes (FolioReader-style), new:
  - **Entry points.** "Note" appears in the selection menu; nothing is created
    unless a note is saved. The highlight menu has "Note" / "Edit Note", and the
    highlight list has swipe actions (Delete, Note / Edit Note).
  - **Editor.** `YabrPDFNoteEditorViewController`, a page sheet built with
    `themedNavigationController`.
  - **Storage.** `PDFAnnotationManager.setNote` saves through `didAddHighlight`
    (same id, upsert). A blank note clears it.
  - **On-page marker.** A small square in the top-right corner of the last
    line, built by `PDFHighlightAnnotations.noteMarker`. In light and sepia it's
    a highlight annotation in the same colour, so it reads as a darker patch
    with the text readable. It doesn't change margin detection, which counts a
    pixel as ink only when every channel is below 200.
  - **Rejected marker: custom `draw(with:in:)`.** PDFKit composites such
    annotations in a separate layer: on screen they are opaque, ignore the
    multiply blend, and skip the dark inversion.
  - **Export.** `annotatedExportDocument()` builds a fresh copy of the
    original file with standard annotations; the note goes in the first line
    annotation's `contents`, and there are no markers. The pages on screen are
    untouched.
- Dark-theme annotations: PDFView composites annotations over the page tile
  after `PDFPage.draw` (so over the already-inverted dark page), and multiplies
  markup annotations. In dark this left highlights as tinted text only, and
  Underline / strike-out invisible.
  - **Dark form.** `YabrPDFView.highlightAppearance` (`.dark`, set in
    `applyThemePalette`) rebuilds highlights: translucent filled squares, a
    2 pt bar for Underline (PDFKit doesn't fill a 1 pt square), and a bright
    square marker. Squares are composited normally.
  - **Snapshots.** Jump masks and dark page-turn covers use
    `PDFPageWithBackground.drawAsDisplayed`. It draws the page content
    (`drawPDFPage`), inverts in dark, then the annotations as PDFView does:
    highlights as an opaque multiply fill. `PDFPage.draw` draws them paler.
  - **Verified with `recordVideo`** on 26.5 and 18.5. Dark turns and toggles
    show no colour change. On light and sepia jumps the snapshot text renders
    slightly heavier than the tiles (it always did), and PDFKit draws on-screen
    highlights ~1-2 px taller than their bounds.
  - **List-delete fix.** Deleting from the highlight list now goes through
    the annotation manager. It used to bypass `activeHighlights`, and deleting
    the last row of a section used `deleteRows` after removing the section.
- #55 preload experiment (2026-09-29, iOS 26.5; temporary tile-draw log in
  `PDFPageWithBackground.draw`, since removed):
  - **When tiles render.** PDFKit renders a page's tiles only once the page
    is current, taking about 260-270 ms for a Width-fit page.
  - **Nothing renders ahead.** None of these made PDFKit draw the next page
    early: single-page mode, `usePageViewController(true)`, horizontal
    continuous mode (zero draws of the off-screen neighbour while idle), or a
    hidden second `PDFView` on the next page (tile caches are per view).
  - **What you see.** In `recordVideo`, parts of the new page stay a blurry
    low-res placeholder for ~140-190 ms after each light-mode turn.
  - **Only remaining option.** An app-side prerendered cover
    (`viewportSnapshot`-style), held until the page's tile draws stop. Its
    text must render like PDFKit's tiles, which are lighter than the
    current snapshots.
  - **Industry practice.** pdf.js, Nutrient (PSPDFKit), KOReader/MuPDF and
    AndroidPdfViewer all use their own renderers. They render neighbouring
    pages ahead in the direction of travel into a page-bitmap cache, give the
    visible page priority with cancellable prefetch, and tile only when zoomed.
  - **Chosen direction.** Option A: a hybrid PDFView plus prefetched cover.
    Snapshot fidelity is validated first.
  - **Fidelity check** (real `simctl io screenshot`, compared inside the page,
    iOS 26.5):
    - **Tile resolutions.** PDFKit renders tiles at two levels: exactly the
      screen resolution (`scaleFactor` x screen scale) and 100% zoom x screen
      scale (downscaled for display).
    - **Image covers never match exactly.** Every image cover differs on glyph
      edges: `viewportSnapshot` averages 8.5 per pixel, a page image at
      exact resolution 6.4, and one at 3 px/pt downscaled by Core Animation
      5.7. Ink totals match; no whole-pixel shift helps.
    - **A second PDFView matches.** A `YabrPDFView` on the same page with the
      same viewport (`applyViewport(restore(...))`), rendered behind and then
      brought to the front, has zero difference except under the tap-zone
      labels (alpha 0.01), which the cover sat above in the test.
    - **So the prefetch cover should be a second PDFView** placed below the tap
      labels and the theme overlay, as `jumpMaskView` is.
  - **Direction.** Triple buffer behind a `PDFReaderSurface` container that
    owns 1-3 `YabrPDFView`s and all per-view state.
    1. Pure refactor with one view.
    2. Buffers with a cover policy.
    3. Takeover policy.
  - **Gesture-priority experiment** (iOS 26.5 and 18.5, real taps in the
    harness).
    `YabrPDFView` was moved into a container, and its four app tap recognizers
    plus the app's `UIEditMenuInteraction` were moved onto the container. The
    delegate stays the view and uses `location(in: self)`. Results:
    - tapping a highlight shows the app's highlight menu, not PDFKit's markup
      menu;
    - long press selects text, and the system edit menu shows the app items;
    - corner single-tap and edge-strip double-tap turn pages.
    - **Caveats.** PDFView has its own `UIEditMenuInteraction` (text selection)
      that must stay on the PDFView. A view moved to a new parent at runtime
      needs `translatesAutoresizingMaskIntoConstraints = true`, or its
      constraints drop and it collapses. Tap zones are the bottom corners
      (single tap) and 50 pt edge strips (double tap).
    - **Harness quirk.** In a freshly started window-hosted test, the
      text-selection system menu appears only after a sheet has been presented
      once, with or without the container.
    - The same checks pass on iPhone 16 (iOS 18.5).
  - **Step 1 done.** `PDFReaderSurface` hosts the single `YabrPDFView`.
    `controller.pdfView` is read from the surface; nothing stores it, and the
    controller observes the surface's relayed notifications. The surface owns:
    - the theme overlay, jump mask and loading cover;
    - the tap zones and labels, and the app's four taps with their delegate
      rules;
    - the highlight edit-menu interaction;
    - the highlight model (`highlights`, sources, appearance,
      `highlightTapped`, inject/remove/export/hit-testing).

    `YabrPDFView` keeps what is per view: viewport, snapshot, placeholders,
    `buildMenu`, and taps off highlights (`handleTap`). `pdfViewAux` has its
    own surface.
  - **Found by hand in step 1.** PDFKit makes its taps (including the text
    interaction's double tap on `PDFDocumentView`) wait for recognizers
    attached to the PDFView, but not for ones on an ancestor. The surface
    declares that PDFKit's taps inside the page view wait for its page-turn and
    highlight-menu taps. Without this, a side-zone double tap also selected a
    word.
  - **Step 2 done: buffers with a cover policy.**
    - **Buffers.** `PDFReaderSurface` keeps two non-interactive `YabrPDFView`
      buffers behind the active view, showing its neighbours
      (`refreshPageBuffers`, after neighbour detection completes).
    - **Shared viewport.** `singlePageViewport(for:in:)` is shared by the page
      on screen and the buffers.
    - **Covering.** `handlePageChange` calls `coverWithBuffer(showing:)`, which
      brings the matching buffer above the active view, below the overlays.
      - It requires the same scale, margins and content size, and a top left
        within 24 px.
      - It then copies the active view's exact inset and offset
        (`alignScrollPosition`). The same fit can land 1-4 px apart depending
        on how each view got there, most on iOS 18.
    - **Handover.** The cover ends once the active view has drawn the page at
      its own resolution and then been quiet for 60 ms (timeout 1 s).
      `PDFPageRenderTheme` logs draws per page and resolution. PDFKit first
      draws a new page at 100% zoom (the old blurry/heavy intermediate), then
      at `scaleFactor x screen scale`.
    - **Dark.** Buffered dark turns skip the freeze and page-change snapshot
      masks: a snapshot's glyphs render heavier than tiles, visible as the mask
      faded.
    - **Verified by recording** (iOS 26.5): light and dark turns each change
      once, from the old page to the final new page. There are no placeholder,
      intermediate or bright frames, and the handover is at codec-noise level.
  - **Test-environment deadlock.** PDFKit analyses visible pages with Vision
    (`PDFPageAnalyzerV2` on the document's `formFillingQueue`). About 67 test
    documents with pending analyses exhaust GCD's worker pool, so the global
    utility queue never runs again in that process. Two fixes:
    - Margin detection uses its own serial queue; private queues still get
      threads.
    - `buildTocList` runs on the main thread (it also raced on `tocList`).

    In the app only one document is open, and analysis is serial per document.
  - **Step 3 done: takeover.** `turnPage(forward:)` (the prev/next buttons and
    tap zones) first calls `surface.takeOver(showing:viewport:)`.
    - **What it does.** A buffer holding the target page and already rendered
      at its resolution (draw log newer than when it got the page) becomes the
      active view. The old active view becomes a buffer that already shows the
      new neighbour.
    - **What moves.** Notification relay, interactivity and accessibility, the
      delegate, selection (cleared) and the highlight menu (dismissed).
    - **Page change.** The surface posts the page change itself;
      `handlePageChange` consumes it (`consumeTakeover`), with no cover and no
      mask.
    - **Fallback.** Otherwise the PDFKit turn plus cover from step 2. Under
      dark, only a rendered buffer replaces the masks: an unrendered one shows
      PDFKit's white placeholder, which a recording caught on fast turns.
    - **Recordings** (iOS 26.5): normal light and dark turns change once. Turns
      faster than a buffer can render (~250 ms) fall back as before: light
      shows the placeholder for a few frames, dark shows the snapshot masks.
    - **Test trap.** A scale near 1.0 counts as rendered, because PDFKit's
      first pass renders every page at 100% zoom.
  - **Consent prompts in tests.** Tests skip the ATT and ad-consent (UMP)
    prompts (`UITestingConfiguration.skipsConsentPrompts`: the UI-test launch
    argument or the unit-test host). Otherwise the UMP form covered the UI
    tests and window-hosted sessions.
  - **Hand-check tips.** After `xcodebuild` reboots a simulator, `attach` the
    Simulator tool before the first tap, or the running test app is killed.
    Run the next session without `simctl shutdown` to keep the connection.
- In tests, `ReadingSessionManagerTests.tearDown` sets `AppContainer.shared =
  nil`; window-hosted harnesses must recreate one before adding a window or the
  host's SwiftUI `appContainer` environment default asserts.
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
