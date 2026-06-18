# P2 A11 Plan: Split CalibreData.swift

## Approach

`CalibreData.swift` is currently a 1307-line mixed model file containing core
Calibre domain values, reading-position values, annotation payloads, sync/search
tasks, API response DTOs, plugin preferences, activity records, a generic array
helper, and the `CalibreServerConfigProvider` service protocol. The split should
be a zero-behavior-change move first: preserve type names, initializers, access
levels, Codable keys, Hashable/Equatable behavior, and existing call sites while
moving related declarations into smaller files.

The safest implementation strategy is to keep `CalibreData.swift` temporarily as
a compatibility shell or delete it only after the moved files are registered in
the Xcode target and the full build is green. Avoid changing Realm schema,
network semantics, Codable payload shapes, or `ModelData.shared` dependencies in
this A11 pass.

## Scope

- In:
  - Split declarations currently in `Models/CalibreData.swift` into focused
    model files.
  - Preserve the current public/internal API surface and behavior.
  - Register all new Swift files in `YetAnotherEBookReader.xcodeproj`.
  - Add lightweight compile/behavior tests only where the split risks accidental
    initializer, Codable, or identity changes.
  - Update memory-bank handoff notes after implementation.
- Out:
  - Do not refactor `CalibreBook` formatting/rating logic or plugin fallback
    lookups in this pass.
  - Do not move Realm schema objects from `RealmModel.swift`.
  - Do not redesign `CalibreServerService`, repositories, managers, or V2
    search/category services.
  - Do not change Codable field names, activity logging behavior, or network
    request task payloads.

## Proposed File Layout

- `Models/CalibreCoreModels.swift`
  - `CalibreServer`
  - `CalibreLibrary`
  - `CalibreBook`
  - `CalibreSyncStatus`
- `Models/ReadingPositionModels.swift`
  - `BookDeviceReadingPosition`
  - `BookDeviceReadingPositionHistory`
  - `BookDeviceReadingPositionHistory.getReadingStatistics(...)`
  - Keep `BookReadingPositionLegacy` removed or leave it as a historical comment
    only if retaining comments is important for traceability.
- `Models/CalibreHighlightStyle.swift`
  - `BookHighlightStyle`
  - This file alone should import `UIKit` because the style color helper returns
    `UIColor`; most other moved model files should only need `Foundation`.
- `Models/CalibreTasks.swift`
  - `CalibreBookTask`
  - `CalibreBooksMetadataRequest`
  - `CalibreBooksTask`
  - `CalibreLibraryProbeTask`
  - `CalibreLibrarySearchTask`
  - `CalibreBookSetLastReadPositionTask`
  - `CalibreBookUpdateAnnotationsTask`
- `Models/CalibrePayloadModels.swift`
  - `CalibreBookLastReadPositionEntry`
  - `CalibreBookFormatMetadataEntry`
  - `CalibreBookUserMetadataEntry`
  - `CalibreBookEntry`
  - `CalibreBookAnnotationHighlightEntry`
  - `CalibreBookAnnotationBookmarkEntry`
  - `CalibreBookAnnotationsResult`
  - `CalibreBookAnnotationsMap`
  - `CalibreLibraryBooksResult`
- `Models/CalibreSyncModels.swift`
  - `CalibreCustomColumnInfo`
  - `CalibreCustomColumnDisplayInfo`
  - `CalibreLibraryCategoryKey`
  - `CalibreUnifiedCategoryKey`
  - `CalibreLibraryCategoryValue`
  - `CalibreProbeServerRequest`
  - `CalibreProbeLibraryRequest`
  - `CalibreSyncLibraryRequest`
  - `CalibreSyncLibraryResult`
  - `CalibreSyncLibraryBooksMetadata`
  - `CalibreLibraryCategory`
  - `CalibreCdbCmdListResult`
- `Models/CalibrePluginModels.swift`
  - `CalibreDSReaderHelperPrefs`
  - `CalibreCountPagesPrefs`
  - `CalibreGoodreadsSyncPrefs`
  - `CalibreDSReaderHelperConfiguration`
- `Network/CalibreActivityModels.swift`
  - `CalibreActivity`
  - `CalibreActivityStart`
  - `CalibreActivityFinish`
  - These are network/activity-log concepts and already have
    `CalibreActivityLogger.swift` nearby.
- `Models/CalibreServerConfigProvider.swift`
  - `CalibreServerConfigProvider`
- `Models/Array+Chunks.swift`
  - `Array.chunks(size:)`
  - Alternatively move to an existing utility area if the project prefers not to
    create one-file extensions.

## Action Items

- [x] Create the new files above with the same declarations copied verbatim from
      `CalibreData.swift`, using the narrowest required imports per file.
- [x] Move core domain types first (`CalibreServer`, `CalibreLibrary`,
      `CalibreBook`, `CalibreSyncStatus`) and build to catch dependency-order or
      import mistakes early.
- [x] Move reading-position and highlight-style declarations, keeping UIKit
      import isolated to `CalibreHighlightStyle.swift`.
- [x] Move task structs and Codable payload models, preserving all `CodingKeys`,
      default values, optionality, and custom decoders.
- [x] Move sync/category/plugin preference models, keeping existing names and
      nested type names unchanged so decode fixtures and call sites remain valid.
- [x] Move activity classes near the network logger and move
      `CalibreServerConfigProvider` into its own protocol file.
- [x] Remove moved declarations from `CalibreData.swift`; the file was deleted
      via `xcode_XcodeRM` once all new files were registered in the project.
- [x] Register every new Swift file in the app target and Catalyst target, then
      verify no moved test-only files were accidentally added to app targets.
- [x] Add or update focused tests for the highest-risk split boundaries:
      `CalibreServer`/`CalibreLibrary` IDs and hashing, `CalibreBook.inShelfId`,
      custom-column/plugin Codable decoding, and `BookHighlightStyle`
      class/color mapping. New file: `YetAnotherEBookReaderTests/CalibreDataSplitTests.swift` (20 cases).
- [x] Run `xcodebuild build` and the narrowest relevant unit tests first, then
      run the full test command when practical. Result: 87 unit tests + 1 UI test
      green. Catalyst build still blocked by a pre-existing SPM package product
      resolution issue unrelated to the split.

## Validation

- Build:

```bash
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
```

- Preferred full validation:

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData
```

- Suggested targeted tests after adding model-boundary coverage:

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:YetAnotherEBookReaderTests/CalibreDataSplitTests
```

## Risks

- `CalibreLibrary` and `CalibreBook` still reach into `ModelData.shared` for
  plugin-derived display helpers. A11 should not fix that, but the split should
  keep these types in `Models` rather than moving them into network DTO files.
- `CalibreBookUserMetadataEntry` intentionally carries dynamic `Any?` fields
  while only decoding the `table` key through Codable. Preserve that odd shape
  exactly.
- `BookHighlightStyle` is model-like but imports UIKit; isolating it avoids
  spreading UIKit through pure DTO files.
- Xcode project drift is the main operational risk. New files must be present in
  both app build variants before deleting declarations from `CalibreData.swift`.
- Moving task structs into `Network` may look tempting, but several managers and
  services consume them. Keep task DTOs in `Models` unless implementation proves
  there is no cross-layer churn.

## Open Questions

- None blocking. Default to a mechanical zero-behavior split; defer semantic
  cleanup of `CalibreBook`, plugin fallback access, and dead commented legacy
  code to later refactoring tasks.
