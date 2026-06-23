# Shelf View Style Alignment Plan

Created: 2026-06-23

## Objective

Align the new SwiftUI shelf views with the legacy UIKit `ShelfView` visual
language while preserving the A21 SwiftUI architecture:

- Keep `RecentShelfView`, `SectionShelfView`, `RecentShelfViewModel`, and
  `SectionShelfViewModel` as the active implementation.
- Do not reintroduce the external UIKit `ShelfView` dependency.
- Treat `/Users/peterlee/git/ShelfView-iOS` as the visual/reference source for
  sizing, shelf tiles, status icons, header styling, and interaction placement.

## Reference Summary

Legacy UIKit source:

- `ShelfView-iOS/ShelfView/Classes/Dimens.swift`
  - Grid item: `150 x 200`
  - Book cover: `120 x 160`
  - Grid spacing: `10`
  - Cover aspect: `3:4`
  - Spine width: `8`
- `ShelfCellView.swift`
  - Per-cell shelf background image: `left`, `center`, or `right`
  - Book cover centered inside a physical shelf tile
  - Cover shadow radius `10`, opacity `0.7`
  - `spine.png` overlay at the cover leading edge
  - Status/refresh icon at cover lower-left
  - Options icon at cover lower-right
  - Progress badge at cover upper-right, text `FIN` at 100%
  - Selection control at cover upper-left in edit mode
- `ShelfHeaderCellView.swift`
  - `header.png` stretchable header background
  - Centered title with brown shadow
- `PlainShelfView.swift`
  - Background color `#C49E7A`
  - Fixed-height rows, no interitem spacing, empty shelf blocks fill the viewport
- `SectionShelfView.swift` and `SectionShelfCompositionalView.swift`
  - Header height `32`
  - Section rows use the same `150 x 200` shelf cell visual
  - Empty placeholder tiles maintain continuous shelf rows

Current SwiftUI implementation:

- `ShelfBookCard.swift`
  - Generic card layout with `110 x 160` rounded covers
  - SF Symbol/capsule status badges
  - Progress bar and title below the cover
  - Context menu replaces the old visible options affordance
- `RecentShelfView.swift`
  - Adaptive `LazyVGrid`, 20 pt spacing, grouped-system background
- `SectionShelfView.swift`
  - `LazyVStack` sections with simple text headers
  - Horizontal rows with `LazyHStack`, 16 pt spacing, no shelf tile filler

## Alignment Strategy

Implement the alignment as a visual-layer modernization, not a behavioral
rewrite. Keep the existing SwiftUI data flow and callbacks, but introduce a
legacy-compatible style system and rebuild the card/section composition around
that style.

## Staged Work

### Stage 1: Visual Inventory And Baseline

- Capture current SwiftUI Recent and Section shelf screenshots on iPhone and
  iPad simulator sizes.
- Use `ShelfView-iOS/iphone.png` and `ShelfView-iOS/ipad.png` as legacy visual
  references.
- Record the target metrics from `Dimens.swift`, `ShelfCellView.swift`, and
  section layout classes in the implementation PR notes.

Verification:

- Screenshots exist for current SwiftUI and legacy references.
- A short checklist confirms which legacy traits are target parity and which are
  intentionally modernized.

### Stage 2: Add SwiftUI Shelf Style Metrics

- Add a small `ShelfVisualStyle` or `ShelfStyleMetrics` type under
  `Views/ShelfView/`.
- Centralize:
  - tile width/height: `150 x 200`
  - cover size: `120 x 160`
  - header height: `32`
  - shelf background color: `#C49E7A`
  - spine width: `8`
  - badge/icon frames and offsets
  - cover shadow values
- Add a status-to-asset mapper for all `ShelfBookStatus` cases.

Verification:

- Unit tests cover status icon mapping and progress label formatting, including
  `100 -> FIN`.
- No view model or domain behavior changes.

### Stage 3: Bring Legacy Assets Into The App Target

- Copy the legacy shelf assets into the app asset catalog or an equivalent
  bundle-managed resource location:
  - `left.png`
  - `center.png`
  - `right.png`
  - `header.png`
  - `spine.png`
  - `options.png`
  - `icon-book-ready.png`
  - `icon-book-noconnect.png`
  - `icon-book-hasupdate.png`
  - `icon-book-downloading.png`
  - `icon-book-local.png`
  - `icon-book-updating.png`
- Ensure assets are registered for both iOS and Catalyst targets.
- Prefer the original raster assets over approximating the shelf with SwiftUI
  shapes, because the legacy look is image-driven.

Verification:

- Build confirms all assets resolve in both app targets.
- A preview or lightweight runtime check renders every asset by name.

### Stage 4: Rebuild `ShelfBookCard` Around Legacy Cell Composition

- Replace the generic rounded-card composition with a fixed shelf tile layout:
  - shelf tile background (`left`, `center`, or `right`)
  - centered cover area
  - book title placeholder only when the cover is unavailable
  - `spine.png` overlay when a cover is present
  - progress badge at top-right of the cover
  - status/refresh asset at lower-left
  - visible options affordance at lower-right when applicable
  - edit selection control at top-left
- Keep existing callbacks:
  - tap opens/reads the book
  - details/refresh/delete/history/actions remain wired through the current
    SwiftUI context menu or visible option button, depending on platform fit
- Keep accessibility labels for visible image-only controls.

Verification:

- Snapshot/manual screenshot comparison shows cover size, badge placement, spine,
  and status icon placement match the UIKit reference.
- Existing shelf interaction tests still pass.

### Stage 5: Align Recent Shelf Grid Layout

- Replace the current adaptive `110...150` card grid with legacy shelf-row
  metrics:
  - row height `200`
  - tile minimum width `150`
  - no vertical/interitem gap between shelf tiles
  - continuous row backgrounds using `left`, `center`, `right`
- Add placeholder shelf tiles to fill incomplete rows and viewport remainder,
  matching `PlainShelfView.buildShelf`.
- Use the legacy shelf background color instead of grouped-system background.
- Preserve pull-to-refresh, edit toolbar, and modal presentation behavior.

Verification:

- Recent shelf shows continuous shelf rows even with partial data and empty
  bottom space.
- Rotation/resizing does not leave broken left/center/right tile sequencing.

### Stage 6: Align Section Shelf Layout And Headers

- Replace simple text section headers with a stretchable `header.png` based
  SwiftUI header view.
- Apply header height `32`, centered title, and legacy shadow styling.
- Use fixed-height shelf rows for each section and fill incomplete rows with
  placeholder tiles.
- For horizontally scrolling section rows, preserve the compositional legacy
  behavior:
  - each item group width follows `150 + gridSpacing` when content overflows
  - short sections expand to fill available width without breaking shelf tile
    sequencing
- Keep the existing library filter toolbar behavior unless a separate product
  decision asks to change it.

Verification:

- Section shelf header, row height, and tile continuity match the legacy
  `SectionShelfCompositionalView` reference.
- Library filtering and editing behavior remain unchanged.

### Stage 7: Validate Across Data States

Exercise representative data states:

- No books
- One book
- Partial row
- Multiple complete rows
- Multiple libraries/sections
- Long book titles
- Missing cover URL
- Cover load failure
- Each `ShelfBookStatus`
- Progress values: `0`, middle values, `100`
- Edit mode selected/unselected

Verification:

- Screenshots for iPhone portrait, iPhone landscape, and iPad.
- No overlapping text or controls.
- Status icon and progress badge stay within the cover bounds.

### Stage 8: Build And Regression Checks

- Run focused shelf tests first:

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -only-testing:YetAnotherEBookReaderTests/RecentShelfViewModelTests -only-testing:YetAnotherEBookReaderTests/SectionShelfViewModelTests
```

- Then run the full app test command if the implementation changes shared shelf
  display models, asset registration, or Xcode project membership:

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData
```

- Run Catalyst build if asset target membership or shared SwiftUI view layout is
  changed:

```bash
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader-Catalyst -destination 'platform=macOS,variant=Mac Catalyst' build
```

## Non-Goals

- Do not restore `RecentShelfController.swift`, `SectionShelfController.swift`,
  or any UIKit shelf wrapper.
- Do not re-add the external `ShelfView` package dependency.
- Do not change shelf business logic, download behavior, Realm access, or view
  model responsibilities.
- Do not attempt unrelated navigation or settings redesign.

## Risks And Mitigations

- Risk: Legacy UIKit constants are rigid and may not scale cleanly across
  Catalyst/iPad widths.
  - Mitigation: centralize metrics and compute tiles-per-row responsively while
    preserving the 150 pt base tile.
- Risk: Asset target membership can drift between iOS and Catalyst.
  - Mitigation: verify both schemes after adding assets.
- Risk: Visible options button plus SwiftUI context menu can duplicate actions.
  - Mitigation: keep one primary visible affordance and use context menu only as
    supplemental platform behavior.
- Risk: Empty tile filler can complicate identity/diffing.
  - Mitigation: keep filler models view-local and separate from
    `ShelfBookItem` domain data.

## Recommended Implementation Order

1. Add style metrics and tests.
2. Add assets and verify bundle loading.
3. Refactor `ShelfBookCard` to legacy tile composition.
4. Align `RecentShelfView` layout and filler tiles.
5. Align `SectionShelfView` headers, row layout, and filler tiles.
6. Capture screenshots and run focused/full validation.
