# UI Test Modernization

## Core Offline UI Test Suite (2026-07-11)

- Expanded `YetAnotherEBookReaderUITests` to cover launch/tab navigation,
  Recent mock-book details, Browse reopen behavior, and Settings mock-server
  visibility.
- The `--ui-testing-mock-library` path skips local Documents-library scanning,
  synchronously seeds and persists fixed mock data, publishes shelf updates,
  and avoids simulator user data and network dependencies.
- Initial verification used iPhone 17 Simulator with isolated `/tmp`
  DerivedData and SPM caches; `build-for-testing` and all four UI tests passed.

## Browse Search And Batch Operations (2026-07-11)

- Expanded the isolated mock library to three persisted Realm books with
  distinct title, author, tag, series, modification date, and EPUB size. Only
  `Mock Book Title` appears in Recent; Alpha and Beta are Browse-only.
- Added accessibility contracts and UI coverage for search/no-results/clear,
  title sorting, batch selection, Select All/Clear/Cancel, and EPUB confirmation
  without starting a download.
- Added fixture and selection-state unit coverage. Two complete seven-test runs
  passed; recorded runtimes were about 236s and 292s.

## Browse Categories And Filters (2026-07-11)

- Seeded offline Authors, Tags, and Series category caches with generation,
  URL, count, and metadata values derived from the three mock books. UI test
  initialization writes caches directly without category refresh or network
  sync.
- Added normalized accessibility identifiers and coverage for root Authors
  filtering, Series search/clear, and Tags multi-select/remove/clear.
- `build-for-testing` passed, focused Browse/category tests passed 53/53, and
  two complete ten-test runs passed in about 283s and 279s.

## FolioReader Reading Flow (2026-07-11)

- Added the self-authored, CC0 `UI Test Fixture.epub`; no third-party book
  content is redistributed. Mock initialization installs it into the isolated
  EPUB cache, selects `YabrEPUB`, and seeds horizontal paged preferences.
- `UITestingConfiguration` remains in the FolioReader configuration layer, so
  `AppContainer.swift` has no direct FolioReaderKit import.
- Added unique Reader accessibility contracts for screen, content, position,
  and close. The deterministic Recent flow opens the EPUB, completes a real
  page transition, closes, and returns to Recent. Position changes come only
  from FolioReader page callbacks, not transient content offsets.
- `build-for-testing` passed, focused tests passed 63/63, and two complete
  eleven-test runs passed with 0 failures at about 309s each.

## Journey Consolidation And Performance Plan (2026-07-11)

- Consolidated 11 scenarios into five independently launched XCTest journeys
  while retaining 11 named `XCTContext` activities. Shared helpers fast-path
  satisfied waits, reuse element queries, record timing, and restore Browse
  search, sort, batch-selection, and category-filter state deterministically.
- Added `UITestPerformance.xctestplan` and the dedicated
  `YetAnotherEBookReader-UI-Performance` scheme. Parallel experimentation is
  isolated from the default development scheme.
- `build-for-testing`, sequential execution, and performance-plan execution
  passed all five journeys and 11 activities without fixed sleeps or state
  leakage. `git diff --check` passed.
- Xcode 26.5/CoreSimulator scheduling remains unstable: one
  `test-without-building` run created Clone 1 and Clone 2, while subsequent runs
  fell back to Clone 1 only. Recorded wall-clock times were about 382s, 322s,
  and 356s. The requested 180-second target was not met; this deviation was
  explicitly accepted, and stable two-clone scheduling remains a toolchain
  follow-up rather than a guaranteed project capability.
