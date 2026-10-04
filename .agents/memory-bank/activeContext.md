# Active Context

## Current Focus

`codex/yabr-pdf-optimization`: fix YabrPDF single-page margin-crop viewport
placement (content right of center, top offset / drift after page turns).

## Current Branch Notes

- Reading regions (#97 spreads + columns, #19 column detection). Options
  `spreadMode` (Off/Auto/On) and `columnsMode` (Off/Auto), per book, default Off.
  - **Storage.** Optional Realm columns (schema 143): a nil row reads Off. A
    non-optional enum column reads "" on old rows and crashes RealmSwift's
    enum decode in every reader.
  - **Detection** (`PDFMarginCropController`).
    - `PageVisibleContentValue.regions` holds the regions in reading order,
      crop-relative and top-down like `bounds`; empty means the page reads
      whole. The region modes are part of `PageVisibleContentKey`
      (`init(pageNumber:options:)`).
    - **Spreads:** split at the crop box centre. Each half goes through
      `detectContentEdges` on a `PageRaster.cropped` sub-raster, so the spine
      shadow is the half's inner edge artifact. Auto needs a landscape page
      plus `hasSpreadSpine`: a blank or dark strip ≥ 2% of the width, the full
      height of the central sixth (a word space in a slide title is narrower).
      With one blank half, the page reads whole, fitted to the other half.
    - **Columns:** `PDFColumnDetector` runs on a `PDFInkMap` of the content
      box (or of each spread half). It classifies windows of about 4 lines,
      merges them into bands, and moves boundaries into the blank gap between
      blocks. It needs ≥ 40% of the content in columns.
      - **Text rule:** a split band stays split only if each column reads like
        running text: ≥ 4 lines of text height (≤ 4% of the content height)
        inked across ≥ half the column with no gap over an eighth of it,
        covering ≥ 30% of the column's inked height. Tables (label ... number)
        and figure grids read whole; a column that also holds a figure passes.
      - **Vertical text (TtB_RtL):** tiers (段). The ink map is turned a
        quarter (`turnedForVerticalText`), detected as columns, and turned
        back: read from the right, band by band, top tier first.
  - **Reading** (`YabrPDFViewController+ReadingFlow`, `PDFReadingFlow.swift`).
    - `PDFPageReadingPlan` holds every screen of every region
      (`PDFPageViewportFitter.screens`: equal steps, ≥ 10% overlap, last
      screen at the far margin; one screen if the content ends on screen by
      using the far margin), in display space. **A page read whole is one
      region** (its content box): in Page mode any page longer than the view
      at its fit steps a screen at a time. `readingPlan` is nil only for a
      page shown in one step (and in Scroll mode), which keeps the old
      fit/restore path.
    - The current step is derived from the view itself (top-left page point
      plus scale), not stored, so drags, zooms and restores need no
      bookkeeping.
    - **`turnPage`:** steps within the page first (`stepWithinPage`: apply the
      viewport plus the jump mask). Otherwise it sets `readingFlow`'s pending
      `.first`/`.last` before PDFKit or `takeOver` changes page;
      `handlePageChange` consumes it. Prev onto a long page lands on its last
      screen, not its saved position.
    - Buffers are prepared at the same arrival targets (next `.first`,
      previous `.last`), so `PDFReaderSurface` stays page-keyed.
    - Rotation and option changes set a pending `.region`
      (`readingRegionOnScreen`); it resolves to that region's step nearest the
      saved point (`stepIndex(nearestUpperLeft:…region:)`).
    - **Jumps** go through `jump(to:)` (destination, selection, highlight
      rect, bookmark). Targets: `.destination(rect)` lands on the last step of
      the region holding it that shows it; `.lowerLeft(point)` (bookmarks save
      `currentDestination`, the visible lower-left) the step with that corner.
      In single-page mode the page changes with `go(to: page)`: PDFKit's jump
      to a point or selection scrolls on sideways after `handlePageChange`.
      On the page on screen the step is applied directly under the mask.
    - **Page indicator:** `12 / 300 · 3/7` (turns) on a page with a plan;
      refreshed on page change, step, and when the bars come back.
    - **Step masks:** the next and previous step's masks are drawn ahead on a
      background queue (`prepareJumpMasks`, layouts from
      `PDFPageViewportFit.pageToView`), matched by page, size and layout and
      shifted by PDFKit's few-point landing offset. Dropped on theme,
      highlight, buffer release and memory warnings. Measured on a heavy scan:
      a step takes 1–4 ms with a prepared mask, 36–56 ms drawing it. A step's
      mask holds past 400 ms (≤ 1 s) while its newly shown tiles draw; a drag
      fades it.
  - **Still deferred:**
    - unmasked same-page steps (buffer takeover: viewport-keyed buffers plus
      per-view tile attribution);
    - two-axis stepping for over-wide regions;
    - per-page overrides; regions in Scroll mode.
- Margin-crop detection fixes (#94, #96), `PDFMarginCropController`:
  - **Ink by luminance** (Rec. 601 Y < 200): coloured text counts. The thumbnail
    is B G R A in memory; `PixelChannelOffsets` reads the real channel order.
  - **The reader's highlights are excluded.** Detection runs on a `PDFPage.copy()`
    without annotations carrying `highlightId`. Every highlight colour is ink by
    luminance, and a highlight on the first lines moved the top edge by ~37 pt
    (green highlights already did before). File annotations still count.
  - **Scans cross the whole page** (were stopped at mid-page). Text in one half,
    such as a chapter's last lines or a late opening, is found from the far edge.
  - **Side scans are scaled by the detected text height**, not by white lines in
    the outer quarters. On short pages the old scaling cut ~13 pt off line starts.
  - Folios were already ignored on full pages (too sparse to anchor, too far to
    pull in). #96's chapter-end symptom was the mid-page scan limit.
  - **Ragged edges (#93):** after the dense side edge, `extendBorderOverSparseInk`
    walks outward over any ink within the detected text rows, across gaps up to
    `max(4, lines/100)` px (about a word space). A few long lines, a long word or
    a trailing dash are kept. A marginal note further out, and running heads or
    folios outside the rows, are not. Both side edges are covered, so ragged-left
    text works too.
    - #93's scale jumps (Width mode) and left-margin wiggle (Page/Height mode
      only) were left alone by choice. Width mode already pins the left margin.
  - **Lines set off by extra space (#92):** `extendBorderAcrossLineGaps` still
    walks across gaps up to ~1.5x the body's line gap (`maxGap`, ~7 px for 11/15
    text). Across a wider gap, up to 4x the line pitch, it hops to the ink beyond
    only when that ink is:
    - line-like: at least half the body's first ink run, and 3 px;
    - outside the outer tenth of the page, where running heads and folios sit.
    - Hops repeat: paragraph tail → heading → body.
    - The gap alone can't tell a heading from a running head. In
      `BookPageGenerator` the head sits ~29 pt above the body; the probe's
      heading-to-body gap was ~32 pt.
    - The same hop keeps a one-line footnote below the body (#96's footnote case).
      It was cut off before.
  - **Scan artifacts (#95):** `PageRaster.edgeArtifactWidth` finds a scanner
    border or binding shadow on each edge:
    - a run of lines with at least half their pixels inked;
    - starting at the edge, allowing a thin light strip first;
    - ending within the outer tenth. A dark run that goes on is a full-bleed
      picture or tinted page, so it gives 0.
    - Each pass starts after the artifact on its own edge (`skip`). It also
      leaves out those on the other edges from its lines (`pixels`).
    - Before this, a gutter shadow inked every row. The top pass then saw no
      line gaps and stopped extending, which dropped paragraph tails.
    - `PageRaster` bundles the thumbnail bytes, size, row stride and channel
      offsets that were passed to every scan as separate parameters.
  - Scanned-page noise (specks) is still only limited by the walks' gap limits
    and the hop's minimum line height.
- Margin detection performance (2026-10-04), `PDFMarginCropController`:
  - **Pipeline.** `thumbnail(of:)` renders the media box once, without the
    reader's highlights. `analyze(_:key:)` reads it through
    `PageRaster.reading`, which uses the CGImage's own size and row stride
    and keeps its pixel data alive while read. Then come the edge passes,
    spread halves and columns.
  - **Removed:**
    - the crop-box render, which only fed a print;
    - the debug overlay (`thumbImage`), drawn at screen scale: 17 MB per
      Letter page at 3x, kept for up to 9 pages. Its viewer,
      `thumbController`, was never shown.
  - **Page number.** It now always opens `YabrPDFNavigationPageVC`
    (`presentNavigation`, shared with the toolbar's list button). It used to
    need a cached detection, so it did nothing on a book opened in Scroll mode.
  - **Reading lines.** `PageRaster.density` and `inkedPixels` walk a line
    through the bitmap in exact integers: darkness 255000 − (299r + 587g +
    114b) per ink pixel. The 14 colours exactly on the threshold, which the
    old floating-point sum rounded to ink, stay ink.
    - `PDFInkMap` keeps a `PDFInkTable` of ink counts for its own area. The
      map turned for vertical text is a view of it.
    - Whole-page summed-area tables were tried and dropped: building them
      (1–2.6 ms at -O) cost more than a text page's passes.
  - **Options changes.** The page on screen is re-detected from its render:
    `recentRenders` keeps three (the page and its neighbours, since a buffer
    refresh can detect a neighbour on the main thread between slider steps).
    It is main-thread only, and is dropped on `clearCache` and on memory
    warnings.
  - **Same results.** An A/B run against the old detector over every page the
    suite and the benchmark detect (575) found no difference.
    `PDFPageRasterTests` pins lines and ink maps to per-pixel reading.
  - **Benchmark.** `PDFMarginDetectionBenchmarkTests` is opt-in. Run it with
    `TEST_RUNNER_YABR_BENCHMARK=1 xcodebuild test …
    -only-testing:YetAnotherEBookReaderTests/PDFMarginDetectionBenchmarkTests`.
    - For optimized numbers, add `SWIFT_OPTIMIZATION_LEVEL=-O` and use its own
      derived data (`/tmp/YabrDerivedDataO`).
    - Points of Interest intervals (`PDFMarginDetection`, `PDFMarginRender`,
      `PDFMarginEdges`, `PDFMarginRegions`) profile it on a device.
  - **Numbers.** Median ms per page, iOS 26.5 simulator on the Mac, -O,
    before → after. The re-detection under other options is one slider step.

    | Page | Detection | Under other options |
    |---|---|---|
    | text | 23.2 → 3.0 | 23.2 → 0.39 |
    | blank | 23.4 → 2.4 | 23.4 → 2.0 |
    | paper, columns | 30.0 → 4.5 | 30.0 → 1.2 |
    | vertical tiers | 27.6 → 2.8 | 27.6 → 1.0 |
    | spread | 19.6 → 4.6 | 19.6 → 1.7 |
    | 300 dpi scan | 53.6 → 19.3 (18.7 render) | 53.6 → 0.45 |

    - Debug analysis is 1.2–2× faster.
    - `YabrPDFMarginCropTests` went from 175.6 s to 162.6 s; the unit suite
      from 214 s to 198 s.
  - **Not done:**
    - Our own rendering: drawing into our own context was within 10% of
      `PDFPage.thumbnail`.
    - 8-bit gray: CoreGraphics' gray isn't Rec. 601 on encoded values.
    - A smaller raster.
  - **Follow-up.** `refreshPageBuffers` (after a cover ends) can detect a
    neighbour on the main thread while the analysis queue is still detecting
    it.
- Rotated pages (`page.rotation` ≠ 0) are detected and fitted as displayed:
  - **`PDFPageDisplaySpace`** (in `PDFPageViewportFitter.swift`) maps a page box
    to display space and back. PDFKit turns pages clockwise; display space has a
    bottom-left origin with y up, like page space.
  - **Detection.** `PDFPage.thumbnail` draws the page turned and aspect-fits it
    into the requested size. Asking for the unturned media-box size gave a
    shrunken raster (612×472 for a 90° Letter page) read at full scale.
    Detection now asks for the turned size, runs the passes in display space
    (so the top, line gaps and ragged edges are the ones the reader sees), and
    maps the rect back. `visibleBounds` still returns crop-relative,
    top-down page space.
  - **Fit.** `singlePageViewport` runs the fitter in display space. That
    includes the saved-axis keep: a NaN axis stays NaN through the turn. Only
    `pageAnchor` is mapped back; `applyViewport` converts through PDFKit.
  - **Saved position.** `getPagePoint` converts the view's top-left corner as a
    point. Taking `(minX, maxY)` of the visible rect in page space is wrong on a
    turned page.
  - `testRotatedPageFitShowsContent` no longer expects a failure. The remaining
    expected failures, `testProbeGoTo…`, record PDFKit's own `go(to:)`
    behaviour.
- Auto-hiding bars (FolioReader style):
  - **Behaviour.** A tap-zone page turn (not the toolbar arrows) and a drag of the page view on
    screen hide the nav bar and toolbar. The drag is detected by a target on
    PDFKit's scroll-view pan, added in `YabrPDFView.layoutSubviews`.
    A plain page tap toggles them (`surface.onPageTap` → `requestBarToggle`):
    - shown bars hide at once;
    - hidden bars show after `barRevealDelay` (0.3 s). The reveal is cancelled
      when a selection appears (a double tap selects a word).
    - `handleTap` returns whether the tap was used: a menu dismissed, a
      selection cleared, or a link followed.
  - **Layout.** The page is fitted to `pageLayoutInsets`, the navigation
    controller's own safe area without its bars, so the bars float over it.
    This supersedes "the top margin starts below the nav bar" below.
  - **No movement.** `setReaderBarsHidden` moves the bars' share of the safe
    area into `additionalSafeAreaInsets` while they are hidden. The page views'
    safe area, PDFKit's scroll insets and the placement don't change.
  - **Verified.** A recording shows the area between the bars unchanged at
    codec-noise level across toggles.
  - **PDF Options** (`presentOptions`) hides the bars while it is open and
    restores their previous state on dismissal (`DismissAwareHostingController`).
    - It is a popover anchored at the top right of the view with no arrow,
      because the Options button hides with the bar.
    - On compact width it is the popover's adaptive sheet: medium/large detents,
      undimmed at medium, so the page shows above it.
    - Page taps don't toggle the bars while it is open.
    - No `fixedSize()`: it clipped the options in the sheet.
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
    - **Handover.** The cover ends once the active view has drawn every tile it
      shows (timeout 1 s). PDFKit first draws a new page at 100% zoom (the old
      blurry/heavy intermediate), then at `scaleFactor x screen scale`.
      (Superseded detail: it used to wait for any draw plus 60 ms of quiet; see
      the review fixes below.)
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
    - **What it does.** A buffer holding the target page, laid out like the
      active view and with every tile it shows drawn since it got the page,
      becomes the active view. The old active view becomes a buffer that already shows the
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
  - **Review fixes (2026-09-30)**, from a peer review of `main...79ed2e96`:
    - **Tile-level draw log.** All page views' tiles render on one queue
      (`PDFKit.PDFTilePool.workQueue`), so a draw cannot be tied to a view.
      Tiles can be identified, though (experiment, identical on iOS 18.5 and
      26.5):
      - Tiles are 1024 px squares with a 1 px border, anchored at the display
        box origin; tile (c, r) draws with ctm translation (1 - 1024c, 1 - 1024r).
      - PDFKit draws the visible tiles plus a ring of margin tiles.
      - `PDFPageTile` and `PDFPageRenderTheme.tileDrawCounts` implement this.
    - **What uses it.** "Rendered" means every tile the view shows has drawn
      since the buffer got its page or a new scale. It used to mean a single
      draw, so a half-rendered buffer could take over.
    - **Cover handover.** A covering buffer that had not finished counts as
      owing its missing tiles (`coverOwedTiles`); the active view has drawn
      those only on their second draw.
    - **Fallback.** Draws off the grid (another OS or Catalyst tile size) fall
      back to "any draw plus 60 ms quiet". `testRenderedPageDrawsArePDFKitTiles`
      guards the grid.
    - **Takeover also** posts a scale change (so `lastScale` follows) and skips
      buffers laid out differently (direction, RTL, box) until they are
      refreshed.
    - **Snapshots.** `drawAsDisplayed` now draws PDFKit annotations in box space
      (`PDFAnnotation.draw(with:in:)` applies the box transform itself). Before,
      underlines and dark squares were offset on pages with a non-zero crop
      origin. `invertedImage` shares `PDFPageWithBackground.invert`.
    - **Dark freeze.** It copies the screen (`snapshotView(afterScreenUpdates:
      false)`), or keeps a mask that is still showing, instead of drawing the
      page again.
    - **Scale changes.** `lastScale` changes from `handleScaleChange`
      (`isRecordingScale`) only persist; they no longer restyle the chrome.
    - **Continuous mode** drops the viewport's extra inset.
    - **Progress.** It is reported for restored positions too. The transient
      first page during `invalidateRenderedPages` is ignored
      (`isReattachingDocument`); the old early return had hidden it.
    - **Status bar.** It is light only in the reader workspace
      (`presentationID != nil`); the book preview keeps UIKit's default.
    - **Not changed.** The placeholder detection's dependence on private layer
      names is already guarded by `testDarkInvertsPDFKitPagePlaceholders`.
  - **Page dragged off screen (2026-09-30, iPad, TtB_RtL + Height).** Two causes:
    - **Padding counted twice.** PDFKit applies `pageBreakMargins` twice per
      side, so `padPageBreakMargins` (one view-excess per side, meant to keep
      the page between flush left and flush right) let a narrower page be
      dragged almost entirely off either edge.
    - **Fix: `confineScrollRange`**, which runs after every `applyViewport`,
      sets the scroll range (via `viewportExtraInset`, which may be negative).
      Along an axis where the page fits the view it stays inside; otherwise it
      keeps covering the view; the fitted placement stays reachable. A pinch
      zoom keeps the old range until the next viewport.
    - **Stale saved axis.** Switching TtB_RtL from Width to Height kept the
      saved top-left x, which put the page at the left of the view. A saved
      axis is now kept only while the content overflows the view along it.
    - **RtL centering.** TtB_RtL content that fits the width (e.g. Page fit on
      an iPad in portrait) is now centered horizontally, mirroring LtR. Content
      wider than the view still starts at the right margin.
    - **Test-deadlock recurrence.** Four extra window harnesses (3 pages each)
      tipped the PDFKit Vision / GCD-pool deadlock (main thread stuck in a
      `dispatch_group_wait` inside UIKit bounding-path layout). New layout
      tests should reuse one harness across configurations.
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
