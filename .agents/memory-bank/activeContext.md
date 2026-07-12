# Active Context

## Current Focus

- Advanced Reader QA v2 is implemented locally across the Yabr model/network/UI
  boundary. The deployed DSReaderHelper wire protocol differs from the original
  cross-project draft, so `DSReaderHelperConnector` adapts the internal
  `ReaderSelectionContext` contract to the deployed top-level
  `book/position/selection/retrieval_scope/external_contexts` request and maps
  its response back into Yabr's `AdvancedQAResponse`.

## Current Branch Notes

- PDF and Folio selection menus now open `AdvancedQAView`; Folio consumes the
  UI-independent `FolioReaderReferenceResolving` API for locator/reference
  candidates and caps reverse lookup at the selected/current page and CFI;
  missing location fails closed without external reference evidence. PDF menu
  and floating selection controls share the same persisted QA readiness gate.
  Readium has a minimum-context builder but no new selection-menu
  hook because the current Yabr Readium stack has no legacy dictionary entry to
  replace.
- Advanced QA availability is gated by `GET /dshelper/2/qa/status`, persisted
  with each server's existing DSReaderHelper configuration Realm record; only `enabled == true` and
  `state == "ready"` exposes the QA connector/menu. Configuration decoding is
  tolerant of newer DSReaderHelper payloads that omit legacy reading-position
  and Count Pages keys.
- Retrieval scopes are discovered dynamically from status
  `retrieval_scopes` contract v1 and cached with the status. `AdvancedQAView`
  localizes capability keys with server fallback text, gates scopes by required
  reader context, shows spoiler risk, persists the selected kind, and builds
  related/selected-book parameters. Ready legacy status responses without the
  capability object use an explicitly marked two-scope fallback.
- Advanced QA status and the dynamic retrieval-scope contract are persisted in
  `CalibreDSReaderHelperConfiguration` through the existing
  `CalibreServerDSReaderHelperRealm.configurationData` boundary. App bootstrap
  restores them before reader UI is used. The existing settings refresh button
  and Helper configuration sync remain the explicit update paths; server
  bootstrap performs no QA-specific network request. Status
  `libraries[].sync` is decoded as a compact summary; an
  Advanced QA details screen loads sync jobs and per-book details through the
  paginated v2 endpoints, with a visible legacy fallback when those routes are
  unavailable.
- Advanced QA capability interpretation lives with the other plugin models in
  `CalibrePluginModels.swift` (`CalibreServerDSReaderHelper` and
  `CalibreLibraryPluginPreferences`). `CalibreServerManager` has no QA-specific
  status dictionaries or query/update API; it only coordinates generic Helper
  configuration persistence during bootstrap/config sync.
- Generic Helper configuration refreshes preserve the separately detected
  Advanced QA status fields instead of replacing the whole persisted payload.
  Sync-job pagination and error handling live in dedicated settings ViewModels;
  the SwiftUI views only render state and forward user actions.
- QA requests send `mode` and the App's preferred BCP-47 response language.
  DSReaderHelper owns mode-specific query construction so Cortex remains a
  generic RAG backend; legacy requests without mode keep their original query.
- Removed the obsolete `readingPositionColumn*` options from
  `CalibreDSReaderHelperPrefs.Options`; older helper payloads containing those
  keys remain decodable because Codable ignores unknown fields.
- Live smoke on 2026-07-12 succeeded against Calibre
  `192.168.11.65:8080` / DSReaderHelper `192.168.11.65:8081`; the QA response
  included RAG contexts and citations. Focused build/tests should use
  `/tmp/YabrDerivedData-AdvancedQA` while this work remains uncommitted.
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
