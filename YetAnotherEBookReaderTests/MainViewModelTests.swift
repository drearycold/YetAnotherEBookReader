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
        mockAppContainer = MockAppContainerFactory.makeContainer(testName: "MainViewModelTests-${UUID().uuidString}")
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
}
