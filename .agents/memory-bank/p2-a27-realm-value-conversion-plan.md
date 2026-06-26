# P2-A27 Realm Value Conversion Boilerplate Plan

## Context

P2-A27 tracks the remaining boilerplate and drift risk in Realm object to domain
value conversions. Earlier milestones already reduced the blast radius:

- P0/A05 introduced repositories for servers, libraries, books, annotations,
  reading positions, search cache, and category cache.
- P2/A11 split `CalibreData.swift` into focused domain/payload files.
- P2/A12+A24 split Realm schema files under `Models/Realm/` and moved Readium
  preference mapping out of the model layer.
- P2/A16, A17, and A21 removed several direct Realm dependencies from major
  SwiftUI views.

Current status: repository boundaries solve part of A27, but conversion rules
are still duplicated or spread across Realm models, repositories, managers,
services, and reader adapters.

## Current Conversion Map

Core Realm/domain conversions:

- `Models/Realm/CalibreServerRealm.swift`
  - `CalibreServer.init(managedObject:)`
  - `CalibreServer.managedObject()`
- `Models/Realm/CalibreBookRealm.swift`
  - `CalibreBook.init(managedObject:library:)`
  - `CalibreBook.managedObject()`
  - embedded JSON decoding/encoding for formats, identifiers, and user metadata
  - legacy `readPosData` migration into `ReadingPositionRepositoryProtocol`
- `Models/Realm/BookReadingPositionRealm.swift`
  - `BookDeviceReadingPosition.init(managedObject:)`
  - `BookDeviceReadingPosition.managedObject()`
  - `BookDeviceReadingPositionHistory` conversions
- `Models/Repositories/LibraryRepository.swift`
  - manual `CalibreLibraryRealm` to `CalibreLibrary` mapping
  - manual `CalibreLibrary` to `CalibreLibraryRealm` mapping
- `Models/Repositories/AnnotationRepository.swift`
  - `BookBookmarkRealm.toValue()` and `BookBookmarkRealm.init(value:)`
  - `BookHighlightRealm.toValue()` and `BookHighlightRealm.init(value:)`
- `Models/Realm/BookAnnotationRealm.swift`
  - Realm annotation to Calibre annotation upload payload mappings

Remaining scattered callers and compatibility bridges:

- `CalibreBookManager.convert(bookRealm:)`,
  `CalibreBookManager.convert(library:bookRealm:)`, and
  `CalibreBookManager.queryLibrary(for:)`
- `ModelData.convert(...)`, `ModelData.queryLibrary(for:)`, and
  `ModelData.getBookRealm(forPrimaryKey:)` as compatibility facades
- `BookDetailViewModel.convert(bookRealm:)` as a view-model bridge
- `LibrarySearchService` and `RealmSearchCacheStore` construct
  `CalibreBook(managedObject:library:)` directly
- `ReadingPositionViewModel` maps `BookDeviceReadingPositionRealm` directly for
  debug state
- `FolioReaderView/Providers.swift` contains FolioReader-specific conversions
  for highlights, bookmarks, and reading positions
- `ReadiumView/ReadiumPreferenceAdapter.swift` correctly keeps Readium-specific
  preference conversions outside `Models/`

## Problems To Solve

- Field drift: adding a persisted field can require updates in multiple mapping
  sites.
- Mixed responsibilities: some conversion code also performs legacy migration,
  primary-key construction, JSON blob compatibility, or remote payload mapping.
- Boundary leakage: services and view models still instantiate domain values
  from Realm objects directly.
- Update semantics are implicit: read mappings, new object construction, partial
  Realm updates, and list replacement use different local idioms.
- Generic abstraction risk: Realm thread confinement and resolver-dependent
  relationships make reflection-style or macro-style conversion risky today.

## Scope

In scope:

- Centralize reusable Realm/domain mapping helpers.
- Preserve existing Realm schema, class names, persisted property names, and
  primary keys.
- Keep mappings explicit and testable.
- Move repository-facing read/write conversion through shared helpers.
- Reduce `CalibreBook(managedObject:library:)` and `BookDeviceReadingPosition`
  direct construction outside approved mapping/repository files.

Out of scope:

- Realm schema changes or migration version bumps.
- Replacing repositories or redesigning persistence ownership.
- Moving reader-engine adapter conversions that are intentionally engine
  specific, such as FolioReader and Readium adapter mappings.
- Swift macros/code generation in the first pass.
- Broad UI refactors unrelated to conversion call sites.

## Recommended Architecture

Use a small explicit mapping layer instead of a broad generic converter:

- Add `Models/Realm/RealmDomainMapping.swift` or focused files such as
  `CalibreRealmMappers.swift`, `AnnotationRealmMappers.swift`, and
  `ReadingPositionRealmMappers.swift`.
- Prefer methods named by intent:
  - `toDomain(...)`
  - `makeRealmObject()`
  - `applyDomain(_:)`
  - `primaryKey(...)`
- Keep resolver-dependent mappings explicit:
  - server mapping needs no resolver
  - library mapping needs `ServerResolver`
  - book mapping needs `LibraryResolver`
- Keep remote API payload mappings separate from Realm/domain mappings:
  - annotation upload payload mapping can stay near annotation domain models or
    in an annotation sync mapper, but should not be mixed into base Realm object
    mapping.
- Add list/JSON helper utilities only where they remove repeated code without
  hiding Realm write ownership.

## Staged Plan

### A27-S1 Inventory And Golden Tests

Goal: freeze current mapping behavior before moving code.

Actions:

- Add mapper-focused tests covering:
  - `CalibreServer` round trip
  - `CalibreLibrary` round trip including custom columns
  - `CalibreBook` round trip including authors, tags, formats, identifiers,
    user metadata, shelf state, and dates
  - `BookDeviceReadingPosition` and history round trips
  - `BookBookmark` and `BookHighlight` round trips
- Include edge cases for empty authors/tags, malformed or absent JSON data, and
  missing optional Realm fields.
- Record allowed legacy quirks, such as `authorFirst` falling back to
  `"Unknown"` and old format data compatibility.

Validation:

- Run the new mapper tests.
- Run existing `CalibreDataSplitTests`, annotation repository tests, and reading
  position repository tests.

### A27-S2 Extract Explicit Domain Mappers

Goal: move reusable mapping into a named persistence boundary with no behavior
change.

Actions:

- Extract `CalibreServerRealm.toDomain()` and
  `CalibreServer.makeRealmObject()`.
- Extract `CalibreLibraryRealm.toDomain(server:)`,
  `CalibreLibrary.makeRealmObject()`, and custom-column data helpers.
- Extract `CalibreBookRealm.toDomain(library:)` and
  `CalibreBook.makeRealmObject()`.
- Extract `BookDeviceReadingPositionRealm.toDomain()` and
  `BookDeviceReadingPosition.makeRealmObject(bookId:)`.
- Move annotation `toValue()` / `init(value:)` into the same mapper family or
  rename to the shared naming style.

Validation:

- Mapper tests from A27-S1 must remain green.
- `git diff` should show movement/renaming with minimal logic changes.

### A27-S3 Centralize Repository Callers

Goal: make repositories the first consumers of the extracted mappers.

Actions:

- Update `RealmServerRepository`, `RealmLibraryRepository`,
  `RealmBookRepository`, `RealmAnnotationRepository`, and
  `RealmReadingPositionRepository` to use mapper helpers.
- Keep Realm opening and write transactions inside repositories.
- Avoid passing live Realm objects out of repository APIs except explicit legacy
  bridge methods that already exist.
- Where repositories still expose a Realm object bridge, document it as
  compatibility-only.

Validation:

- Repository unit tests.
- Full app build.
- `rg` check for old mapper names and direct initializer use in repositories.

### A27-S4 Reduce Manager, Service, And ViewModel Conversion Bridges

Goal: remove duplicated conversion shims outside the persistence boundary.

Actions:

- Replace direct `CalibreBook(managedObject:library:)` calls in
  `LibrarySearchService` and `RealmSearchCacheStore` with repository or mapper
  helpers.
- Collapse `CalibreBookManager.convert(...)` into a thin compatibility wrapper
  over the repository/mapper, then update callers that can depend directly on
  the repository-facing value API.
- Keep `ModelData.convert(...)` only as a compatibility facade until all callers
  are migrated.
- Move `BookDetailViewModel.convert(bookRealm:)` callers toward value-based
  dependencies where practical.
- Keep `ReadingPositionViewModel` debug-only Realm reads isolated or route them
  through `ReadingPositionRepositoryProtocol`.

Validation:

- `rg -n "CalibreBook\\(managedObject|BookDeviceReadingPosition\\(managedObject"`
  should only report approved mapper or compatibility files.
- Existing BookDetail, search, shelf, and reading-position tests remain green.

### A27-S5 Standardize Realm Write Helpers

Goal: remove repeated write-side object population while preserving explicit
update semantics.

Actions:

- Add `applyDomain(_:)` methods for mutable Realm objects where partial updates
  are needed.
- Keep `makeRealmObject()` for new detached objects.
- Add small helpers for common Realm list replacement, for example string list
  replacement for authors/tags/toc titles.
- Keep primary-key construction centralized on domain values and Realm classes.

Validation:

- Add tests proving updates preserve primary keys and replace list contents
  correctly.
- Run repository tests that cover save/update paths.

### A27-S6 Remote Payload Boundary Cleanup

Goal: separate Realm/domain conversion from Calibre annotation sync payload
conversion.

Actions:

- Review `BookHighlightRealm.toCalibreBookAnnotationHighlightEntry()` and
  `BookBookmarkRealm.toCalibreBookAnnotationBookmarkEntry()`.
- Prefer value-domain payload conversion:
  - `BookHighlight.toCalibreBookAnnotationHighlightEntry()`
  - `BookBookmark.toCalibreBookAnnotationBookmarkEntry()`
- Keep repository sync merge logic responsible for Realm writes, not payload
  construction.
- Avoid moving FolioReader/Readium adapter mappings into the persistence mapper;
  those remain reader adapter concerns.

Validation:

- Annotation sync tests must cover upload payload generation and remote merge
  behavior.
- Reader adapter tests or existing reader-related tests must still pass.

### A27-S7 Guardrails And Documentation

Goal: make the new boundary easy to follow.

Actions:

- Update `AGENTS.md` and relevant memory-bank context after implementation.
- Add a short comment in mapper files explaining that mappers must return
  detached values and must not cross thread boundaries with live Realm objects.
- Add an `rg` checklist to the implementation handoff:
  - direct `RealmSwift` imports in views
  - direct `CalibreBook(managedObject:)` usage
  - direct `BookDeviceReadingPosition(managedObject:)` usage
  - `realm.create(... value: [String: Any])` outside repository/cache sync paths

Validation:

- Full `xcodebuild test` after implementation.
- Mac Catalyst build if package resolution is healthy; otherwise document the
  known SPM product-resolution blocker.

## Suggested File Layout

Preferred low-risk layout:

```text
YetAnotherEBookReader/Models/Realm/
├── CalibreServerRealm.swift
├── CalibreLibraryRealm.swift
├── CalibreBookRealm.swift
├── BookReadingPositionRealm.swift
├── BookAnnotationRealm.swift
├── CalibreRealmMappers.swift
├── AnnotationRealmMappers.swift
└── ReadingPositionRealmMappers.swift
```

Alternative if the mapper files become too small: keep mappings in the existing
Realm schema files but standardize naming and move repository-only conversion
extensions out of repository files. This is less clean but has lower Xcode
project-file churn.

## Test Targets To Prioritize

- New mapper tests, likely `RealmDomainMappingTests`.
- `CalibreDataSplitTests`.
- `ReadingPositionRepositoryThreadingTests`.
- Annotation repository tests or new focused annotation mapper tests.
- Search/cache tests that touch `RealmSearchCacheStore`.
- BookDetail and shelf view-model tests if compatibility facades are changed.

## Risks

- Realm objects are thread-confined. Mapper helpers must not encourage moving
  live objects across queues, actors, or async boundaries.
- `CalibreBook` mapping depends on a resolved `CalibreLibrary`; hiding that
  resolver behind globals would undo repository isolation.
- `managedObject()` currently creates detached objects. Replacing that with
  in-place update helpers must preserve Realm write ownership.
- JSON blob compatibility for formats, identifiers, user metadata, and custom
  columns can silently regress if tests only cover happy paths.
- Reader adapter mappings look similar to persistence mappings but have
  different ownership; merging them too aggressively would reintroduce the
  Readium/Folio coupling fixed in A12+A24.

## Recommended Next Action

Start with A27-S1 only. Add golden mapper tests around the existing behavior
before moving conversion code. Once those tests are stable, perform A27-S2 as a
zero-behavior extraction and verify that call-site migration in A27-S3/S4 is
mechanical rather than semantic.
