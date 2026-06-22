# P2/A21 Shelf SwiftUI Native Migration Plan

## Status

- Plan date: 2026-06-22
- Scope: migrate the shelf surfaces from UIKit controllers wrapped in SwiftUI to SwiftUI-first views.
- Selected as the next project after P2/A17 because shelf ViewModels already exist and `ShelfDataManager` has moved to `Models/`, reducing the risk of untangling UI and data ownership.
- Current implementation remains UIKit-heavy:
  - `RecentShelfUI` and `SectionShelfUI` are `UIViewControllerRepresentable` wrappers around `UINavigationController`.
  - `RecentShelfController` owns `PlainShelfView`, edit toolbar, delete flow, reading entry, detail modal, progress modal, refresh/download actions, and legacy `UIMenuController` actions.
  - `SectionShelfController` owns `SectionShelfCompositionalView`, diffable snapshots, filler rows, library filter menu, edit toolbar, batch download flow, detail modal, and refresh actions.
  - `RecentShelfViewModel` and `SectionShelfViewModel` exist but still expose ShelfView package types and do not yet own enough value-state for SwiftUI rendering.

## Current Findings

- `RecentShelfController.swift`: 474 lines. High-risk behaviors are read/download branching, delete confirmation, detail modal dismissal after book deletion, reading-position history presentation, and selected-book batch deletion.
- `SectionShelfController.swift`: 543 lines. High-risk behaviors are library filter menu generation, selected-library persistence, snapshot/filler-row construction, selected-book batch download, and refresh/update throttling.
- `RecentShelfUI.swift` and `SectionShelfUI.swift` are thin wrappers and can be replaced once SwiftUI surfaces reach parity.
- `YabrShelfDataModel` already lives in `Models/ShelfDataManager.swift`, but still imports `ShelfView`; A21 should avoid increasing that dependency and should gradually move render-only concepts into app-owned value types.
- Existing tests only lightly cover shelf ViewModels. The migration needs focused tests before replacing controllers.

## Non-Goals

- Do not redesign the shelves visually in the first migration. Match current behavior and layout closely enough to keep user workflows stable.
- Do not remove the `ShelfView` package until SwiftUI shelves have reached parity and all wrappers/controllers are unused.
- Do not move new business logic into `ModelData`; extend shelf ViewModels or app-owned display models instead.
- Do not touch Realm schema or reader engine behavior.

## Target Shape

- `RecentShelfView` and `SectionShelfView` become SwiftUI-first views used directly from `MainView`.
- `RecentShelfViewModel` exposes app-owned display state for recent books, selection, refresh, read/download/delete actions, and modal routing.
- `SectionShelfViewModel` exposes app-owned display state for shelf sections, library filters, selection, refresh, and batch download actions.
- Shared SwiftUI pieces live under `Views/ShelfView/`:
  - `ShelfBookCard`
  - `ShelfSectionView`
  - `ShelfToolbar`
  - `ShelfBookContextMenu`
  - small display models such as `ShelfBookItem`, `ShelfSectionItem`, and `ShelfLibraryFilterItem`
- UIKit controllers remain as a fallback during stages S1-S4 and are deleted only after both shelves are migrated.

## Staged Plan

### A21-S1: Behavior Audit and Safety Net

- Add focused tests around current ViewModel behavior:
  - recent shelf refresh triggers metadata refresh and reachability probe.
  - recent shelf delete/delete-many clears cache and emits shelf update.
  - recent shelf prepare-reading returns nil for missing book and returns reader info for valid book.
  - section shelf filter state keeps only valid library ids.
  - section shelf batch download uses preferred formats only.
- Add display-state tests before changing UI.
- Verification:
  - `xcodebuild test -only-testing:YetAnotherEBookReaderTests/RecentShelfViewModelTests`
  - add/run `SectionShelfViewModelTests`
  - iOS simulator build.

### A21-S2: Introduce App-Owned Shelf Display Models

- Create app-owned value models independent from `ShelfView` rendering types:
  - `ShelfBookItem`
  - `ShelfSectionItem`
  - `ShelfLibraryFilterItem`
  - optional `ShelfSelectionState`
- Keep adapters from existing `BookModel`/`ShelfModelSection` in ViewModels.
- Move library filter construction out of `SectionShelfController` into `SectionShelfViewModel`.
- Move recent shelf read/delete/progress/detail routing decisions out of `RecentShelfController` where possible.
- Verification:
  - display model unit tests.
  - existing shelf tests.
  - compile to confirm UIKit controllers can still use old ShelfView types during transition.

### A21-S3: Build SwiftUI Recent Shelf Behind a Wrapper Boundary

- Add `RecentShelfView` using `RecentShelfViewModel`.
- Implement:
  - refresh button.
  - edit/select mode.
  - select all / clear / delete toolbar.
  - book tap read flow with the same missing/downloading format prompts.
  - long press/context menu for details, refresh, delete/remove, Goodreads, Douban.
  - reading position history modal.
  - detail modal and deletion dismissal behavior.
- Keep `RecentShelfUI` available until parity is verified.
- Verification:
  - `RecentShelfViewModelTests`.
  - iOS build.
  - manual smoke on iPhone and iPad: tap to read, missing format prompt, active download prompt, details, progress, refresh, delete one, delete many, rotate/responsive layout.

### A21-S4: Build SwiftUI Section Shelf

- Add `SectionShelfView` using `SectionShelfViewModel`.
- Implement:
  - sectioned book grid.
  - library filter menu with reset and checkmark state.
  - refresh button.
  - edit/select mode.
  - select all / clear / download toolbar.
  - book tap/long-press detail flow.
  - refresh stale cached formats.
- Replace diffable snapshot filler behavior with SwiftUI layout constraints, keeping empty/filler sections visually stable where needed.
- Verification:
  - `SectionShelfViewModelTests`.
  - iOS build.
  - manual smoke: filter libraries, reset filter, empty section, many sections, select all, clear, batch download, refresh stale formats, detail modal, rotation.

### A21-S5: Switch MainView to SwiftUI Shelves

- Replace `RecentShelfUI` and `SectionShelfUI` usage in `MainView` with `RecentShelfView` and `SectionShelfView`.
- Keep UIKit wrappers/controllers in the project temporarily as fallback until one full test pass and manual smoke are done.
- Verification:
  - full iOS simulator `xcodebuild test`.
  - manual app launch through the four main tabs.
  - confirm modal presentation and tab navigation still work.

### A21-S6: Remove UIKit Shelf Controllers and ShelfView Dependency Usage

- Delete `RecentShelfUI`, `SectionShelfUI`, `RecentShelfController`, and `SectionShelfController` only after SwiftUI parity.
- Remove target memberships and imports for these files.
- Audit whether `ShelfView` is still used by `YabrShelfDataModel`; remove or isolate dependency if possible.
- Verification:
  - `rg "ShelfView|RecentShelfController|SectionShelfController|RecentShelfUI|SectionShelfUI"`.
  - iOS build.
  - full test suite.

### A21-S7: Documentation and Handoff

- Update `AGENTS.md` architecture map if file locations or shelf ownership changes.
- Update `.agents/memory-bank/activeContext.md` with stage completion, test status, and known follow-ups.
- Update `.agents/plans/REFACTOR_PLAN.claude.md` and `.agents/plans/REFACTOR_PLAN.claude.progress.md` after completion.

## Risks

- `ShelfView` models currently encode presentation details such as left/center/right shelf item types. Moving too much at once can break layout parity.
- Shelf interactions mix read/download/delete/detail/progress flows. These must be tested as workflows, not only as rendering.
- SwiftUI sheet/full-screen presentation can conflict if multiple row-level views register modal state. Centralize modal routing in the ViewModel or top-level shelf view.
- Realm objects must not cross async or background boundaries. Pass ids/value types through shelf display models.
- Catalyst and ad-banner behavior may differ from iOS. Keep build checks explicit.

## Recommended Next Action

Start with A21-S1 and A21-S2 only. They are low-risk, keep UIKit shelves running, and create a tested ViewModel/display-state boundary before any visual replacement.
