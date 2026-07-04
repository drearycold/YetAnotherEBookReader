import XCTest

class YetAnotherEBookReaderUITests: XCTestCase {
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
    }

    func testBrowseBookDetailOpensImmediatelyAndCanReopenAfterBack() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-mock-library")
        app.launch()

        let browseTab = app.tabBars.buttons["Browse"]
        XCTAssertTrue(browseTab.waitForExistence(timeout: 10))
        browseTab.tap()

        let testLibrary = app.staticTexts["UI Test Library"]
        XCTAssertTrue(testLibrary.waitForExistence(timeout: 10))
        testLibrary.tap()

        openMockBookDetail(in: app)
        closeMockBookDetail(in: app, listTitle: "UI Test Library")
        openMockBookDetail(in: app)
    }

    private func openMockBookDetail(in app: XCUIApplication) {
        let bookTitle = app.staticTexts["Mock Book Title"].firstMatch
        XCTAssertTrue(bookTitle.waitForExistence(timeout: 10), app.debugDescription)
        bookTitle.tap()

        XCTAssertTrue(app.navigationBars["Mock Book Title"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func closeMockBookDetail(in app: XCUIApplication, listTitle: String) {
        let detailNavigationBar = app.navigationBars["Mock Book Title"]
        let backButton = detailNavigationBar.buttons[listTitle]
        XCTAssertTrue(backButton.waitForExistence(timeout: 10))
        backButton.tap()

        XCTAssertTrue(app.navigationBars[listTitle].waitForExistence(timeout: 10))
    }
}
