import XCTest
import ReadiumNavigator
import ReadiumShared
@testable import YetAnotherEBookReader

final class YabrReaderSettingsViewModelTests: XCTestCase {
    func testCommitWritesEPUBEditorStateBackToValueType() {
        let publication = makePublication()
        let editor = EPUBPreferencesEditor(
            initialPreferences: EPUBPreferences(),
            metadata: publication.metadata,
            defaults: EPUBDefaults()
        )
        editor.theme.set(.dark)
        editor.fontSize.set(1.35)
        editor.scroll.set(true)

        var callbackValues: [ReadiumPreferenceValue] = []
        let model = YabrReaderSettingsViewModel(
            preferences: ReadiumPreferenceValue(),
            publication: publication,
            navigator: nil,
            onPreferencesChanged: { callbackValues.append($0) },
            epubEditor: editor
        )

        model.commit()

        XCTAssertEqual(model.preferences.themeMode, 2)
        XCTAssertEqual(model.preferences.fontSizePercentage, 135)
        XCTAssertEqual(model.preferences.scroll, true)
        XCTAssertEqual(callbackValues, [model.preferences])
    }

    func testCommitWithoutEditorUsesLocalValueAndTriggersSingleCallback() {
        let publication = makePublication()
        var callbackValues: [ReadiumPreferenceValue] = []
        let model = YabrReaderSettingsViewModel(
            preferences: ReadiumPreferenceValue(),
            publication: publication,
            navigator: nil,
            onPreferencesChanged: { callbackValues.append($0) }
        )

        model.preferences.themeMode = 2
        model.preferences.scroll = true
        model.preferences.volumeKeyPaging = true
        model.commit()

        XCTAssertEqual(model.preferences.themeMode, 2)
        XCTAssertEqual(model.preferences.scroll, true)
        XCTAssertEqual(model.preferences.volumeKeyPaging, true)
        XCTAssertEqual(callbackValues.count, 1)
        XCTAssertEqual(callbackValues.first, model.preferences)
    }

    func testUpdateVerticalMarginOnlyMutatesLocalValueAndTriggersCallback() {
        let publication = makePublication()
        var callbackValues: [ReadiumPreferenceValue] = []
        let model = YabrReaderSettingsViewModel(
            preferences: ReadiumPreferenceValue(verticalMargin: 10),
            publication: publication,
            navigator: nil,
            onPreferencesChanged: { callbackValues.append($0) }
        )

        model.updateVerticalMargin(30)

        XCTAssertEqual(model.preferences.verticalMargin, 30)
        XCTAssertEqual(callbackValues.count, 1)
        XCTAssertEqual(callbackValues.first?.verticalMargin, 30)
    }

    private func makePublication() -> Publication {
        Publication(manifest: Manifest(metadata: Metadata(title: "Test Publication")))
    }
}
