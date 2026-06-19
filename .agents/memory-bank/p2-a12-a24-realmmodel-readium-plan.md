# P2 A12+A24 Plan: Split RealmModel.swift And Decouple Readium Types

## Approach

`Models/RealmModel.swift` is still a 1357-line mixed persistence file. It defines
Realm schema classes, value-to-Realm mapping extensions, UI/display helpers,
legacy migration helpers, annotation serialization, PDF options, and Readium
preference conversion. A12 should first split this into focused files with no
schema or behavior change. A24 should then remove the direct
`ReadiumNavigator`/`ReadiumShared` dependency from the model layer by moving
Readium-specific preference conversion into the Readium reader adapter layer.

Treat this as a schema-sensitive refactor. Preserve every Realm object class
name, primary key, persisted property name, default value, `objectTypes` entry,
and migration reference unless the task explicitly becomes a schema migration.

## Current Findings

- `RealmModel.swift` currently contains:
  - `Persistable`
  - Main database objects: `CalibreServerRealm`, `CalibreLibraryRealm`,
    `CalibreBookRealm`, `CalibreActivityLogEntry`,
    `CalibreServerDSReaderHelper`
  - Per-book reader objects: `BookDeviceReadingPositionRealm`,
    `BookDeviceReadingPositionHistoryRealm`, deprecated
    `CalibreBookLastReadPositionRealm`, `BookHighlightRealm`,
    `BookBookmarkRealm`, `PDFOptions`, `ReadiumPreferenceRealm`
  - Mapping extensions for `CalibreServer`, `CalibreBook`,
    `BookDeviceReadingPosition`, `BookDeviceReadingPositionHistory`,
    `BookHighlightRealm`, and `BookBookmarkRealm`
  - `BookDeviceReadingPosition` Calibre CFI encode/decode helpers
  - `PDFOptions` display helpers such as `fillColor` and `isDark`
  - `ReadiumPreferenceRealm` conversions to/from `EPUBPreferences`,
    `PDFPreferences`, `EPUBSettings`, and `PDFSettings`
- `RealmModel.swift` imports `ReadiumNavigator` and `ReadiumShared` only for the
  `ReadiumPreferenceRealm` conversion extension. This is the concrete A24
  coupling to remove.
- `FolioReaderPreferenceRealm` is not in `RealmModel.swift`; it still lives in
  `Views/FolioReaderView/Providers.swift` even though it is part of the per-book
  Realm schema via `BookPreference.getBookPreferenceServerConfig(_:)`.
- `BookPreference.swift` is the per-book Realm schema registry and migration
  entry point. Its `objectTypes` currently include:
  - `BookDeviceReadingPositionRealm`
  - `BookDeviceReadingPositionHistoryRealm`
  - `FolioReaderPreferenceRealm`
  - `BookHighlightRealm`
  - `BookBookmarkRealm`
  - `PDFOptions`
  - `ReadiumPreferenceRealm`
- The app-wide Realm migration in `ModelData.tryInitializeDatabase` references
  `CalibreServerRealm`, `CalibreLibraryRealm`, `CalibreBookRealm`,
  `FolioReaderPreferenceRealm`, `ReadiumPreferenceRealm`,
  `CalibreActivityLogEntry`, and `CalibreServerDSReaderHelper` by class name.

## Scope

- In:
  - Split `RealmModel.swift` into focused Realm schema and mapping files.
  - Move `FolioReaderPreferenceRealm` out of `Views/FolioReaderView/Providers.swift`
    into a model/persistence file without changing its class name or fields.
  - Introduce a Readium-neutral value or mapping boundary so `Models/` no longer
    imports `ReadiumNavigator` or `ReadiumShared`.
  - Keep existing call sites working through compatibility wrappers until the
    Readium reader code has been migrated.
  - Add focused tests around schema registration, primary keys, mapping
    round-trips, PDF option helpers, Readium preference numeric mapping, and
    Folio preference target membership.
- Out:
  - Do not rename Realm classes or persisted properties.
  - Do not bump Realm schema version unless a persisted property is actually
    added/removed/renamed.
  - Do not rewrite repositories or remove legacy Realm bridges in the same pass.
  - Do not implement Readium highlight rendering; A14 still notes that UI
    rendering is pending.
  - Do not redesign `YabrReaderSettingsView`; only move Readium conversion out
    of `Models`.

## Proposed File Layout

### Shared Persistence Infrastructure

- `Models/Realm/Persistable.swift`
  - `Persistable`
- `Models/Realm/RealmModel.swift`
  - Either delete after all declarations move, or leave a short compatibility
    comment during the transition.

### Main Calibre Realm

- `Models/Realm/CalibreServerRealm.swift`
  - `CalibreServerRealm`
  - `CalibreServer: Persistable`
  - `CalibreServer.realmPerf`
- `Models/Realm/CalibreLibraryRealm.swift`
  - `CalibreLibraryRealm`
- `Models/Realm/CalibreBookRealm.swift`
  - `CalibreBookRealm`
  - `CalibreBook: Persistable`
- `Models/Realm/CalibreActivityLogEntry.swift`
  - `CalibreActivityLogEntry`
- `Models/Realm/CalibreServerDSReaderHelperRealm.swift`
  - `CalibreServerDSReaderHelper`

### Per-Book Reader Realm

- `Models/Realm/BookReadingPositionRealm.swift`
  - `BookDeviceReadingPositionRealm`
  - `BookDeviceReadingPosition: Persistable`
  - `BookDeviceReadingPositionHistoryRealm`
  - `BookDeviceReadingPositionHistory: Persistable`
  - deprecated `CalibreBookLastReadPositionRealm`
  - `BookDeviceReadingPosition` Calibre last-read-position entry parsing and
    `encodeEPUBCFI()` / `toEntry()`
- `Models/Realm/BookAnnotationRealm.swift`
  - `BookHighlightRealm`
  - `BookBookmarkRealm`
  - Only Realm schema and generic mapping helpers that do not belong to
    `AnnotationRepository`
- `Models/Realm/PDFOptionsRealm.swift`
  - `PDFOptions`
  - `PDFThemeMode` / `PDFAutoScaler` / `PDFLayoutMode` /
    `PDFReadDirection` / `PDFScrollDirection` `PersistableEnum` conformances
- `Models/Realm/ReadiumPreferenceRealm.swift`
  - `ReadiumPreferenceRealm` persisted fields only
  - Non-Readium helpers such as a neutral theme enum or raw-value mapping if
    needed
- `Models/Realm/FolioReaderPreferenceRealm.swift`
  - `FolioReaderPreferenceRealm`
  - Move from `Views/FolioReaderView/Providers.swift`

### Readium Adapter Layer

- `Views/ReadiumView/ReadiumPreferenceAdapter.swift`
  - `ReadiumPreferenceRealm.toEPUBPreferences()`
  - `ReadiumPreferenceRealm.toPDFPreferences()`
  - `ReadiumPreferenceRealm.update(from: EPUBSettings)`
  - `ReadiumPreferenceRealm.update(from: PDFSettings)`
  - `ReadiumPreferenceRealm.update(from: EPUBPreferences)`
  - `ReadiumPreferenceRealm.update(from: PDFPreferences)`
  - `ReadiumPreferenceRealm.themeColor` if it remains UIKit/reader UI-specific
- Longer-term option:
  - Add `Models/ReadiumPreferenceValues.swift` containing a Readium-neutral
    value type, for example `ReadiumReaderPreferences`, with only primitive
    stored values.
  - Let `ReadiumPreferenceRealm` convert to/from that value type.
  - Let `ReadiumPreferenceAdapter.swift` convert the value type to/from Readium
    `EPUBPreferences` and `PDFPreferences`.

## Action Items

- [ ] Add focused tests that lock the current behavior before moving code:
      primary-key generation, `CalibreBookRealm.RatingDescription`,
      `CalibreBook` round-trip mapping, reading-position round-trip mapping,
      `PDFOptions.fillColor/isDark`, and Readium preference raw-value mappings.
- [ ] Create `Models/Realm/` and move `Persistable`, Calibre server/library/book
      Realm declarations, and their Persistable extensions into focused files.
- [ ] Move activity and DSReader Helper Realm declarations into focused model
      files, preserving the app-wide Realm migration references in
      `ModelData.tryInitializeDatabase`.
- [ ] Move per-book reader persistence declarations into focused files:
      reading positions, annotations/bookmarks, PDF options, Readium preference,
      and FolioReader preference.
- [ ] Register all new files in both iOS app and Catalyst app targets; register
      new test files only in the test target.
- [ ] Build after the mechanical split before starting Readium decoupling.
- [ ] Extract Readium conversions from `RealmModel.swift` into
      `Views/ReadiumView/ReadiumPreferenceAdapter.swift` as a first A24 step,
      leaving method names intact so `YabrReaderSettingsView` and
      `YabrReadium*ViewController` call sites do not churn.
- [ ] If practical in the same pass, introduce a primitive
      `ReadiumReaderPreferences` value type and make `ReadiumPreferenceRealm`
      depend only on that type, while the adapter owns all Readium framework
      conversions.
- [ ] Verify `rg "import Readium" YetAnotherEBookReader/Models` returns no
      model-layer Readium imports after A24.
- [ ] Update `AGENTS.md` and `activeContext.md` after implementation so future
      agents no longer treat `RealmModel.swift` as a monolithic schema file.

## Validation

- Mechanical split build:

```bash
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
```

- Targeted tests to add/run:

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:YetAnotherEBookReaderTests/RealmModelSplitTests
```

- Full validation:

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData
```

- Decoupling checks:

```bash
rg "import Readium|ReadiumNavigator|ReadiumShared|EPUBPreferences|PDFPreferences|EPUBSettings|PDFSettings" YetAnotherEBookReader/Models
rg "FolioReaderPreferenceRealm" YetAnotherEBookReader/Views/FolioReaderView/Providers.swift
```

The first command should not report model-layer Readium imports/types after A24;
the second should not report the Realm class after it is moved to `Models/Realm`.

## Risks

- Realm class names are part of persisted schema identity. Moving files is safe;
  renaming classes or persisted properties is not.
- `FolioReaderPreferenceRealm` migration references exist in both
  `BookPreference.swift` and `ModelData.swift`; moving the class must keep those
  references compiling.
- `PDFOptions` has UI-ish helpers (`fillColor`, `isDark`) used broadly by PDF
  list/chrome code. Moving it is safe, but converting it to a value model should
  be deferred.
- Readium preference conversion has many default-value assumptions. Add tests
  for raw-value mapping before moving conversion out of Models.
- Current model layer still has other non-Realm coupling, such as
  `CalibreBookManager` importing legacy `R2Shared`/`R2Streamer` under
  `canImport(R2Shared)`. That is related architectural debt but not the A24
  target unless the acceptance criteria expand.

## Open Questions

- Should `PDFOptions` remain a Realm object consumed directly by PDF UI for this
  phase, or should a separate `PDFReaderOptions` value type be planned after
  A12? Recommended answer for A12+A24: keep `PDFOptions` as-is and only move it
  to a focused file.
