# FolioReader Highlight Position Restore Implementation Plan

## Approach

Fix the FolioReader adapter restore path, not FolioReaderKit. The likely failure is that persisted highlights are restored without FolioReaderKit's encoded content fields, causing `Bridge.js` highlight injection to fail and interrupt the page load path that also performs position restoration. Also make highlight application create the provider lazily so initial persisted highlights are not dropped when `applyHighlights(_:)` runs before the provider exists.

## Scope

- In:
  - `Views/FolioReaderView/Providers.swift`
  - `YetAnotherEBookReaderTests/FolioReaderProviderBookIdTests.swift`
  - Relevant context update after implementation
- Out:
  - FolioReaderKit source changes
  - Realm schema changes
  - Calibre sync payload shape changes

## Action Items

1. Add a regression test proving `BookHighlight.toFolioReaderHighlight()` populates `contentEncoded`, `contentPreEncoded`, and `contentPostEncoded`.
2. Add a provider regression test proving `FolioReaderDelegateHighlightProvider.applyHighlights(_:)` returns encoded highlights when queried with the FolioReaderKit runtime book id.
3. Add a container regression test proving `EpubFolioReaderContainer.applyHighlights(_:)` creates the highlight provider when it is currently nil and stores the provided highlights.
4. Add a combined restore regression test: save a canonical reading position and a canonical highlight, then verify FolioReaderKit runtime id queries can restore both.
5. Update `BookHighlight.toFolioReaderHighlight()` to call `highlight.encodeContents()` before returning.
6. Update `EpubFolioReaderContainer.applyHighlights(_:)` to obtain the provider through `folioReaderHighlightProvider(self.folioReader)` instead of only using the optional cached provider.
7. Add a small defensive helper or provider-side guard if needed so every returned `FolioReaderHighlight` has encoded content fields before being handed to FolioReaderKit.
8. Run focused tests:
   `xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData -only-testing:YetAnotherEBookReaderTests/FolioReaderProviderBookIdTests`
9. Run full validation:
   `xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData`
10. Update `.agents/memory-bank/activeContext.md` and `.agents/memory-bank/refactoring-context.md` with the confirmed fix, test result, and current reader adapter boundary.

## Acceptance Criteria

- Reopening a FolioReader EPUB with no highlights still restores the saved position.
- Reopening after adding at least one highlight restores both the saved position and persisted highlights.
- Runtime FolioReaderKit book ids remain accepted, while repository reads/writes remain canonical `book.bookPrefId`.
- Focused FolioReader provider tests and full test suite pass.

## Assumptions

- The observed position failure after adding a highlight is caused by highlight injection failure blocking FolioReaderKit's page load and positioning sequence.
- The existing local FolioReaderKit dependency should be treated as external for this fix.
- Existing untracked files, including `opencode.jsonc`, are unrelated and should not be modified.
