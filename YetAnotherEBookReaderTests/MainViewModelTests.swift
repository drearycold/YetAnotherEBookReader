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

        let presented = await waitUntil { self.viewModel.activeReaderPresentation != nil }
        XCTAssertTrue(presented)
        XCTAssertEqual(viewModel.activeReaderPresentation?.book.inShelfId, book.inShelfId)
        XCTAssertEqual(viewModel.activeReaderPresentation?.source, .shelf)
        XCTAssertFalse(viewModel.activeReaderPresentation?.readerInfo.missing ?? true)
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.activePresentation?.book.inShelfId, book.inShelfId)
        XCTAssertTrue(viewModel.readerWorkspaceViewModel.isPresented)
    }

    func testRecentShelfTapReopensExistingReaderTab() async throws {
        let book = try XCTUnwrap(mockAppContainer.bookManager.readingBook)
        mockAppContainer.bookManager.booksInShelf[book.inShelfId] = book

        viewModel.recentShelfViewModel.tapBook(bookId: book.inShelfId)

        let firstOpen = await waitUntil {
            self.viewModel.readerWorkspaceViewModel.activePresentation?.book.inShelfId == book.inShelfId
        }
        XCTAssertTrue(firstOpen)
        let originalPresentationID = try XCTUnwrap(viewModel.readerWorkspaceViewModel.activePresentationID)

        viewModel.readerWorkspaceViewModel.hideReader()
        XCTAssertFalse(viewModel.readerWorkspaceViewModel.isPresented)

        viewModel.recentShelfViewModel.tapBook(bookId: book.inShelfId)

        let reopened = await waitUntil {
            self.viewModel.readerWorkspaceViewModel.isPresented &&
                self.viewModel.readerWorkspaceViewModel.activePresentationID == originalPresentationID
        }
        XCTAssertTrue(reopened)
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.presentations.count, 1)
        XCTAssertEqual(mockAppContainer.sessionManager.readerPresentations.map(\.id), [originalPresentationID])
    }

    func testReaderPresentationDismissalSyncsSessionState() async throws {
        let book = try XCTUnwrap(mockAppContainer.bookManager.readingBook)
        let readerInfo = mockAppContainer.sessionManager.prepareBookReading(book: book)
        mockAppContainer.openReader(book: book, readerInfo: readerInfo, source: .shelf)
        let presented = await waitUntil { self.viewModel.readerWorkspaceViewModel.activePresentation != nil }
        XCTAssertTrue(presented)

        viewModel.readerWorkspaceViewModel.closeActivePresentation()

        XCTAssertNil(mockAppContainer.sessionManager.activeReaderPresentation)
        XCTAssertFalse(viewModel.readerWorkspaceViewModel.hasReaders)
    }

    func testReaderWorkspaceKeepsTabsWhenHidden() async throws {
        let library = try XCTUnwrap(mockAppContainer.libraryManager.calibreLibraries.first?.value)
        let firstBook = try XCTUnwrap(mockAppContainer.bookManager.readingBook)
        var secondBook = CalibreBook(id: 909, library: library)
        secondBook.title = "Second Reader"
        secondBook.formats = firstBook.formats
        mockAppContainer.bookManager.booksInShelf[firstBook.inShelfId] = firstBook
        mockAppContainer.bookManager.booksInShelf[secondBook.inShelfId] = secondBook

        let firstInfo = mockAppContainer.sessionManager.prepareBookReading(book: firstBook)
        let secondInfo = mockAppContainer.sessionManager.prepareBookReading(book: secondBook)
        mockAppContainer.openReader(book: firstBook, readerInfo: firstInfo, source: .shelf)
        mockAppContainer.openReader(book: secondBook, readerInfo: secondInfo, source: .bookDetail)

        let attached = await waitUntil {
            self.viewModel.readerWorkspaceViewModel.presentations.count == 2
        }
        XCTAssertTrue(attached)
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.activePresentation?.book.inShelfId, secondBook.inShelfId)

        viewModel.readerWorkspaceViewModel.hideReader()

        XCTAssertFalse(viewModel.readerWorkspaceViewModel.isPresented)
        XCTAssertTrue(viewModel.readerWorkspaceViewModel.hasReaders)

        viewModel.readerWorkspaceViewModel.showReader()

        XCTAssertTrue(viewModel.readerWorkspaceViewModel.isPresented)
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.presentations.count, 2)
    }

    func testReaderSceneActivityAttachesPresentation() async throws {
        let book = try XCTUnwrap(mockAppContainer.bookManager.readingBook)
        let readerInfo = mockAppContainer.sessionManager.prepareBookReading(book: book)
        let presentation = mockAppContainer.openReader(
            book: book,
            readerInfo: readerInfo,
            source: .shelf,
            placement: .registryOnly
        )
        let activity = ReaderSceneActivity.make(presentationID: presentation.id, title: presentation.title)

        viewModel.handleReaderSceneActivity(activity)

        let attached = await waitUntil {
            self.viewModel.readerWorkspaceViewModel.activePresentationID == presentation.id
        }
        XCTAssertTrue(attached)
        XCTAssertTrue(viewModel.readerWorkspaceViewModel.isPresented)
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
