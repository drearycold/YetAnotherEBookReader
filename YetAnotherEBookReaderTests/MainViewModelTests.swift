//
//  MainViewModelTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by opencode on 2026/6/18.
//

import XCTest
import SwiftUI
import Combine
@testable import YetAnotherEBookReader

@MainActor class MainViewModelTests: XCTestCase {
    var viewModel: MainViewModel!
    var mockAppContainer: AppContainer!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        mockAppContainer = MockAppContainerFactory.makeContainer(testName: "MainViewModelTests")
        viewModel = MainViewModel(container: mockAppContainer, sessionManager: mockAppContainer.sessionManager)
        cancellables = []
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockAppContainer = nil
        cancellables = nil
    }
    
    func testInitialization() throws {
        XCTAssertEqual(viewModel.activeTab, 0)
        XCTAssertNil(viewModel.alertItem)
        XCTAssertFalse(viewModel.initialTermsAgreementPresenting)
        XCTAssertFalse(viewModel.privacyWebViewPresenting)
        XCTAssertFalse(viewModel.termsWebViewPresenting)
        XCTAssertFalse(viewModel.bookImportActionSheetPresenting)
        XCTAssertNil(viewModel.bookImportInfo)
        XCTAssertFalse(viewModel.consentRequestTriggered)
        XCTAssertNil(viewModel.urlToOpen)
    }
    
    func testOnAppearTermsAccepted() throws {
        UserDefaults.standard.setValue(true, forKey: Constants.KEY_DEFAULTS_INITIAL_TERMS_ACCEPTED)
        viewModel.onAppear()
        XCTAssertTrue(viewModel.consentRequestTriggered)
        XCTAssertFalse(viewModel.initialTermsAgreementPresenting)
    }
    
    func testOnAppearTermsNotAccepted() throws {
        UserDefaults.standard.setValue(false, forKey: Constants.KEY_DEFAULTS_INITIAL_TERMS_ACCEPTED)
        viewModel.onAppear()
        XCTAssertFalse(viewModel.consentRequestTriggered)
        XCTAssertTrue(viewModel.initialTermsAgreementPresenting)
    }
    
    func testAcceptTerms() throws {
        viewModel.acceptTerms()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Constants.KEY_DEFAULTS_INITIAL_TERMS_ACCEPTED))
        XCTAssertFalse(viewModel.initialTermsAgreementPresenting)
        XCTAssertFalse(viewModel.consentRequestTriggered)
    }
    
    func testReportImportError() throws {
        viewModel.bookImportInfo = BookImportInfo(url: URL(fileURLWithPath: "/tmp/foo.epub"), error: .destConflict)
        viewModel.reportImportError()
        XCTAssertNotNil(viewModel.urlToOpen)
        XCTAssertTrue(viewModel.urlToOpen?.absoluteString.contains("destConflict") == true)
    }

    func testShowWelcomeIsFalseWhenDatabaseIsNotReady() throws {
        mockAppContainer.databaseService.realm = nil
        mockAppContainer.booksInShelf.removeAll()

        XCTAssertFalse(viewModel.showWelcome)
    }

    func testShowWelcomeIsTrueWhenDatabaseIsReadyAndShelfIsEmpty() throws {
        XCTAssertTrue(mockAppContainer.isDatabaseReady)
        mockAppContainer.booksInShelf.removeAll()

        XCTAssertTrue(viewModel.showWelcome)
    }

    func testRecentShelfTapPublishesReaderPresentation() async throws {
        let book = try XCTUnwrap(mockAppContainer.bookManager.readingBook)
        mockAppContainer.bookManager.booksInShelf[book.inShelfId] = book

        viewModel.recentShelfViewModel.tapBook(bookId: book.inShelfId)

        let presented = await waitUntil { self.viewModel.presentingEBookReaderFromShelf }
        XCTAssertTrue(presented)
        XCTAssertNotNil(viewModel.readingBook)
        XCTAssertNotNil(viewModel.readerInfo)
        XCTAssertFalse(viewModel.readerInfo?.missing ?? true)
    }

    func testReaderPresentationDismissalSyncsSessionState() async throws {
        mockAppContainer.sessionManager.presentingEBookReaderFromShelf = true
        let presented = await waitUntil { self.viewModel.presentingEBookReaderFromShelf }
        XCTAssertTrue(presented)

        viewModel.presentingEBookReaderFromShelf = false

        XCTAssertFalse(mockAppContainer.sessionManager.presentingEBookReaderFromShelf)
    }

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}
