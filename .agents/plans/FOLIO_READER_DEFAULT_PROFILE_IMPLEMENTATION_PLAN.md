# FolioReader Default Profile Regression Implementation Plan

## Approach

Restore the FolioReader profile behavior lost when `FolioReaderRealmPreferenceProvider` was removed, without bringing that deprecated provider back. Keep the current delegate-based preference persistence path for per-book settings, and add a small profile-store layer to `FolioReaderDelegatePreferenceProvider` so FolioReaderKit can list, load, save, and remove profiles again.

## Scope

- In:
  - `Views/FolioReaderView/Providers.swift`
  - Focused FolioReader preference provider tests
  - Context update after implementation
- Out:
  - FolioReaderKit source changes
  - Realm schema changes
  - Calibre sync payload changes
  - Reintroducing `FolioReaderRealmPreferenceProvider`

## Phase 1 - Baseline And Regression Safety Net

1. Add a focused test fixture for `FolioReaderDelegatePreferenceProvider` using an isolated Realm configuration for profile storage.
2. Add a failing regression test proving a newly created provider returns `["Default"]` from `preference(listProfile: nil)`.
3. Add a failing regression test proving the seeded Default profile contains the legacy defaults:
   - `themeMode = FolioReaderThemeMode.serpia.rawValue`
   - `nightMode = false`
   - `currentFont = "Georgia"`
   - `currentFontSize = FolioReader.DefaultFontSize`
   - `currentFontWeight = FolioReader.DefaultFontWeight`
   - linked vertical/horizontal margins
   - `currentLetterSpacing`, `currentLineHeight`, `currentTextIndent`
   - `doWrapPara = false`
   - `doClearClass = true`
4. Verify the new tests fail before implementation or clearly document if existing behavior unexpectedly passes.

### Phase 1 Validation

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -only-testing:YetAnotherEBookReaderTests/FolioReaderProviderBookIdTests
```

Expected interim result: new Default profile tests fail before implementation.

## Phase 2 - Reconnect Profile Store To Delegate Provider

1. Extend `FolioReaderDelegatePreferenceProvider` initializer to accept `profileRealmConfig: Realm.Configuration?`.
2. Update `EpubFolioReaderContainer.folioReaderPreferenceProvider(_:)` to pass `modelData?.realmConf` into the provider.
3. Add a private profile Realm opener inside the provider. It must return nil safely if the configuration is unavailable or Realm cannot open.
4. Add `ensureDefaultProfile()` that creates `"Default"` in the profile Realm when missing, using the legacy default values from the removed provider.
5. Seed provider `values` from the Default profile during initialization before any book-specific `applyPreferences(_:)` call.

### Phase 2 Validation

- The Default profile list test passes.
- Existing preference get/set behavior remains unchanged for in-memory values.

## Phase 3 - Restore Profile Operations

1. Implement `preference(listProfile filter:)` by reading `FolioReaderPreferenceRealm` ids from the profile Realm, applying the optional filter, and sorting deterministically.
2. Implement `preference(loadProfile name:)` by copying the profile Realm object into provider `values`, then calling `notifyDelegate()` so the current per-book preference row is updated through the existing `ReaderEngineDelegate` path.
3. Implement `preference(saveProfile name:)` by creating or updating a `FolioReaderPreferenceRealm` in the profile Realm from current provider `values`.
4. Implement `preference(removeProfile name:)` by deleting the matching profile Realm object. If `"Default"` is removed, the next `listProfile` or provider initialization must recreate it via `ensureDefaultProfile()`.
5. Add focused tests for save/list/load/remove:
   - Save a custom profile and verify a new provider instance can list and load it.
   - Load a custom profile and verify provider values change.
   - Use a mock `ReaderEngineDelegate` to verify loading a profile emits `didUpdatePreferences`.
   - Remove a custom profile and verify it disappears.
   - Remove Default and verify it is recreated on the next list.

### Phase 3 Validation

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -only-testing:YetAnotherEBookReaderTests/FolioReaderProviderBookIdTests
```

Expected result: all FolioReader provider tests pass.

## Phase 4 - Integration Check And Cleanup

1. Confirm `YabrEBookReader` still applies saved per-book `FolioReaderPreferenceRealm` after provider creation, so book-specific preferences override Default profile seed values.
2. Confirm `preference(setString:)`, `preference(setInt:)`, and `preference(setBool:)` still notify the delegate and do not write directly to per-book Realm.
3. Remove any temporary diagnostics.
4. Run whitespace validation.
5. Run full app test validation.

### Phase 4 Validation

```bash
git diff --check
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData
```

Expected result: full test suite passes.

## Phase 5 - Context Update

1. Update `.agents/memory-bank/activeContext.md` with:
   - confirmed regression root cause
   - restored Default/profile behavior
   - focused and full validation results
2. Preserve unrelated dirty worktree changes. Do not revert existing edits to `YetAnotherEBookReader.xcodeproj/project.pbxproj` or unrelated plan/context files unless they are explicitly part of the implementation.

## Acceptance Criteria

- FolioReader profile menu lists `Default` again.
- `Default` profile is recreated automatically if missing.
- Custom profiles can be saved, listed, loaded, and removed.
- Loading a profile updates the current FolioReader preferences through `ReaderEngineDelegate.didUpdatePreferences`.
- Existing per-book preference persistence remains delegate-driven and continues to override Default profile seed values during reader open.
- Focused FolioReader provider tests and full `xcodebuild test` pass.

## Assumptions

- The original Default profile was global and stored in `ModelData.realmConf`; keep that compatibility behavior.
- No Realm migration is required because `FolioReaderPreferenceRealm` already exists in both relevant Realm configurations.
- The removed `FolioReaderRealmPreferenceProvider` should remain deleted; only its profile semantics should be restored.
