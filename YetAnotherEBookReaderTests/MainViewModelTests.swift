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

    func testShelfStateChangesRefreshWelcomePresentation() async throws {
        let initialSnapshotsArrived = await waitUntil {
            self.viewModel.welcomeShelfStateVersion >= 2
        }
        XCTAssertTrue(initialSnapshotsArrived)

        let baseline = viewModel.welcomeShelfStateVersion

        mockAppContainer.bookManager.isShelfLoaded.toggle()

        let refreshed = await waitUntil {
            self.viewModel.welcomeShelfStateVersion > baseline
        }
        XCTAssertTrue(refreshed)
    }

    func testOpenWelcomeSettingsSelectsSettingsTab() throws {
        viewModel.activeTab = 0

        viewModel.openWelcomeSettings()

        XCTAssertEqual(viewModel.activeTab, 3)
    }

    func testOpenWelcomeBrowseSelectsBrowseTab() throws {
        viewModel.activeTab = 0

        viewModel.openWelcomeBrowse()

        XCTAssertEqual(viewModel.activeTab, 2)
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

    func testReaderWorkspaceKeepsInactiveTabMountedWhenSwitching() async throws {
        let presentations = try makeReaderPresentations(count: 2)
        presentations.forEach { presentation in
            viewModel.readerWorkspaceViewModel.attachPresentation(id: presentation.id)
        }

        XCTAssertEqual(viewModel.readerWorkspaceViewModel.activePresentationID, presentations[1].id)
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.presentationIDs, presentations.map(\.id))
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.mountedPresentationIDs, presentations.map(\.id))

        viewModel.readerWorkspaceViewModel.activatePresentation(id: presentations[0].id)

        XCTAssertEqual(viewModel.readerWorkspaceViewModel.activePresentationID, presentations[0].id)
        XCTAssertEqual(Set(viewModel.readerWorkspaceViewModel.mountedPresentationIDs), Set(presentations.map(\.id)))
        XCTAssertEqual(mockAppContainer.sessionManager.readerPresentations.map(\.id), presentations.map(\.id))
    }

    func testReaderWorkspaceUnmountsOldestInactiveWhenHotMountLimitExceeded() async throws {
        let presentations = try makeReaderPresentations(count: 4)
        presentations.forEach { presentation in
            viewModel.readerWorkspaceViewModel.attachPresentation(id: presentation.id)
        }

        XCTAssertEqual(viewModel.readerWorkspaceViewModel.presentationIDs, presentations.map(\.id))
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.mountedPresentationIDs, presentations.dropFirst().map(\.id))
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.activePresentationID, presentations[3].id)
        XCTAssertEqual(mockAppContainer.sessionManager.readerPresentations.map(\.id), presentations.map(\.id))
    }

    func testReaderWorkspaceLifecycleDistinguishesCloseAndTemporaryUnmount() async throws {
        let closePresentation = try makeReaderPresentations(count: 1, idOffset: 400).first!
        viewModel.readerWorkspaceViewModel.attachPresentation(id: closePresentation.id)
        let closeExpectation = expectation(description: "Close unmount reason")
        let closeReason = UnmountReasonBox()
        let closeObservation = observeUnmountReason(
            from: viewModel.readerWorkspaceViewModel.readerLifecycleEvents(for: closePresentation.id),
            expectation: closeExpectation,
            reason: closeReason
        )

        viewModel.readerWorkspaceViewModel.closePresentation(id: closePresentation.id)

        await fulfillment(of: [closeExpectation], timeout: 1.0)
        closeObservation.cancel()
        XCTAssertEqual(closeReason.value, .close)

        let presentations = try makeReaderPresentations(count: 4, idOffset: 500)
        viewModel.readerWorkspaceViewModel.attachPresentation(id: presentations[0].id)
        let temporaryExpectation = expectation(description: "Temporary unmount reason")
        let temporaryReason = UnmountReasonBox()
        let temporaryObservation = observeUnmountReason(
            from: viewModel.readerWorkspaceViewModel.readerLifecycleEvents(for: presentations[0].id),
            expectation: temporaryExpectation,
            reason: temporaryReason
        )

        presentations.dropFirst().forEach { presentation in
            viewModel.readerWorkspaceViewModel.attachPresentation(id: presentation.id)
        }

        await fulfillment(of: [temporaryExpectation], timeout: 1.0)
        temporaryObservation.cancel()
        XCTAssertEqual(temporaryReason.value, .temporary)
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.presentationIDs, presentations.map(\.id))
        XCTAssertFalse(viewModel.readerWorkspaceViewModel.mountedPresentationIDs.contains(presentations[0].id))
    }

    func testReaderWindowActionsDoNothingWhenUnsupported() async throws {
        guard mockAppContainer.supportsReaderWindows == false else {
            throw XCTSkip("Current test destination supports reader windows.")
        }

        let book = try XCTUnwrap(mockAppContainer.bookManager.readingBook)
        let readerInfo = mockAppContainer.sessionManager.prepareBookReading(book: book)
        mockAppContainer.openReader(book: book, readerInfo: readerInfo, source: .shelf)

        let attached = await waitUntil {
            self.viewModel.readerWorkspaceViewModel.activePresentation?.book.inShelfId == book.inShelfId
        }
        XCTAssertTrue(attached)
        let originalPresentationIDs = mockAppContainer.sessionManager.readerPresentations.map(\.id)

        viewModel.readerWorkspaceViewModel.openEmptyReaderWindow()
        viewModel.readerWorkspaceViewModel.moveActivePresentationToNewWindow()

        XCTAssertEqual(mockAppContainer.sessionManager.readerPresentations.map(\.id), originalPresentationIDs)
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.presentationIDs, originalPresentationIDs)
    }

    func testReaderOpenTargetsInitiatingShelfWorkspace() async throws {
        let secondViewModel = MainViewModel(container: mockAppContainer, sessionManager: mockAppContainer.sessionManager)
        let book = try XCTUnwrap(mockAppContainer.bookManager.readingBook)
        mockAppContainer.bookManager.booksInShelf[book.inShelfId] = book

        secondViewModel.recentShelfViewModel.tapBook(bookId: book.inShelfId)

        let attachedToSecond = await waitUntil {
            secondViewModel.readerWorkspaceViewModel.activePresentation?.book.inShelfId == book.inShelfId
        }
        XCTAssertTrue(attachedToSecond)
        XCTAssertTrue(viewModel.readerWorkspaceViewModel.presentationIDs.isEmpty)
    }

    func testReaderOpenTargetsInitiatingBookDetailWorkspace() async throws {
        let secondViewModel = MainViewModel(container: mockAppContainer, sessionManager: mockAppContainer.sessionManager)
        var book = try XCTUnwrap(mockAppContainer.bookManager.readingBook)
        book.inShelf = true
        mockAppContainer.bookManager.booksInShelf[book.inShelfId] = book

        let detailViewModel = BookDetailViewModel(
            container: mockAppContainer,
            targetWorkspaceID: secondViewModel.readerWorkspaceViewModel.id
        )
        detailViewModel.readBook(book: book)

        let attachedToSecond = await waitUntil {
            secondViewModel.readerWorkspaceViewModel.activePresentation?.book.inShelfId == book.inShelfId
        }
        XCTAssertTrue(attachedToSecond)
        XCTAssertTrue(viewModel.readerWorkspaceViewModel.presentationIDs.isEmpty)
    }

    func testOpenEmptyReaderWindowDoesNotChangeReaderTabs() async throws {
        mockAppContainer.readerWindowSupportOverride = true
        var requestedActivities: [NSUserActivity?] = []
        mockAppContainer.readerWindowRequestHandler = { activity in
            requestedActivities.append(activity)
        }

        let book = try XCTUnwrap(mockAppContainer.bookManager.readingBook)
        let readerInfo = mockAppContainer.sessionManager.prepareBookReading(book: book)
        mockAppContainer.openReader(book: book, readerInfo: readerInfo, source: .shelf)

        let attached = await waitUntil {
            self.viewModel.readerWorkspaceViewModel.activePresentation?.book.inShelfId == book.inShelfId
        }
        XCTAssertTrue(attached)
        let originalPresentationIDs = mockAppContainer.sessionManager.readerPresentations.map(\.id)

        viewModel.readerWorkspaceViewModel.openEmptyReaderWindow()

        XCTAssertEqual(requestedActivities.count, 1)
        XCTAssertNil(try XCTUnwrap(requestedActivities.first))
        XCTAssertEqual(mockAppContainer.sessionManager.readerPresentations.map(\.id), originalPresentationIDs)
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.presentationIDs, originalPresentationIDs)
        XCTAssertTrue(viewModel.readerWorkspaceViewModel.isPresented)
    }

    func testMoveActivePresentationToNewWindowKeepsSourceUntilDestinationAttaches() async throws {
        mockAppContainer.readerWindowSupportOverride = true
        var requestedActivities: [NSUserActivity?] = []
        mockAppContainer.readerWindowRequestHandler = { activity in
            requestedActivities.append(activity)
        }

        let book = try XCTUnwrap(mockAppContainer.bookManager.readingBook)
        let readerInfo = mockAppContainer.sessionManager.prepareBookReading(book: book)
        let presentation = mockAppContainer.openReader(
            book: book,
            readerInfo: readerInfo,
            source: .shelf,
            placement: .registryOnly
        )
        viewModel.readerWorkspaceViewModel.attachPresentation(id: presentation.id)
        let presentationID = presentation.id

        viewModel.readerWorkspaceViewModel.moveActivePresentationToNewWindow()

        XCTAssertEqual(requestedActivities.count, 1)
        let requestedActivity = try XCTUnwrap(requestedActivities.first ?? nil)
        XCTAssertEqual(ReaderSceneActivity.presentationID(from: requestedActivity), presentationID)
        XCTAssertEqual(mockAppContainer.sessionManager.readerPresentations.map(\.id), [presentationID])
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.presentationIDs, [presentationID])
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.activePresentationID, presentationID)
        XCTAssertTrue(viewModel.readerWorkspaceViewModel.isPresented)
        XCTAssertFalse(mockAppContainer.consumeReaderPresentationTransfer(id: presentationID))
    }

    func testMoveActivePresentationToNewWindowDetachesAfterDestinationAttach() async throws {
        mockAppContainer.readerWindowSupportOverride = true
        var requestedActivities: [NSUserActivity?] = []
        mockAppContainer.readerWindowRequestHandler = { activity in
            requestedActivities.append(activity)
        }

        let library = try XCTUnwrap(mockAppContainer.libraryManager.calibreLibraries.first?.value)
        let firstBook = try XCTUnwrap(mockAppContainer.bookManager.readingBook)
        var secondBook = CalibreBook(id: 909, library: library)
        secondBook.title = "Second Reader"
        secondBook.formats = firstBook.formats
        mockAppContainer.bookManager.booksInShelf[firstBook.inShelfId] = firstBook
        mockAppContainer.bookManager.booksInShelf[secondBook.inShelfId] = secondBook

        let firstInfo = mockAppContainer.sessionManager.prepareBookReading(book: firstBook)
        let secondInfo = mockAppContainer.sessionManager.prepareBookReading(book: secondBook)
        let firstPresentation = mockAppContainer.openReader(
            book: firstBook,
            readerInfo: firstInfo,
            source: .shelf,
            placement: .registryOnly
        )
        let secondPresentation = mockAppContainer.openReader(
            book: secondBook,
            readerInfo: secondInfo,
            source: .bookDetail,
            placement: .registryOnly
        )
        viewModel.readerWorkspaceViewModel.attachPresentation(id: firstPresentation.id)
        viewModel.readerWorkspaceViewModel.attachPresentation(id: secondPresentation.id)

        viewModel.readerWorkspaceViewModel.moveActivePresentationToNewWindow()

        XCTAssertEqual(requestedActivities.count, 1)
        let requestedActivity = try XCTUnwrap(requestedActivities.first ?? nil)
        XCTAssertEqual(ReaderSceneActivity.presentationID(from: requestedActivity), secondPresentation.id)
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.presentationIDs, [firstPresentation.id, secondPresentation.id])

        let destinationViewModel = MainViewModel(container: mockAppContainer, sessionManager: mockAppContainer.sessionManager)
        destinationViewModel.handleReaderSceneActivity(requestedActivity)

        let transferred = await waitUntil {
            self.viewModel.readerWorkspaceViewModel.presentationIDs == [firstPresentation.id] &&
                destinationViewModel.readerWorkspaceViewModel.presentationIDs == [secondPresentation.id]
        }
        XCTAssertTrue(transferred)
        XCTAssertEqual(mockAppContainer.sessionManager.readerPresentations.map(\.id), [firstPresentation.id, secondPresentation.id])
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.presentationIDs, [firstPresentation.id])
        XCTAssertEqual(viewModel.readerWorkspaceViewModel.activePresentationID, firstPresentation.id)
        XCTAssertTrue(viewModel.readerWorkspaceViewModel.isPresented)
        XCTAssertEqual(destinationViewModel.readerWorkspaceViewModel.activePresentationID, secondPresentation.id)
        XCTAssertTrue(destinationViewModel.readerWorkspaceViewModel.isPresented)
        XCTAssertEqual(mockAppContainer.sessionManager.activeReaderPresentation?.id, firstPresentation.id)
        XCTAssertTrue(mockAppContainer.consumeReaderPresentationTransfer(id: secondPresentation.id))
        XCTAssertFalse(mockAppContainer.consumeReaderPresentationTransfer(id: secondPresentation.id))
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

    private func makeReaderPresentations(
        count: Int,
        idOffset: Int32 = 200
    ) throws -> [ReaderPresentation] {
        let library = try XCTUnwrap(mockAppContainer.libraryManager.calibreLibraries.first?.value)
        let templateBook = try XCTUnwrap(mockAppContainer.bookManager.readingBook)

        return try (0..<count).map { index in
            var book = CalibreBook(id: idOffset + Int32(index), library: library)
            book.title = "Reader \(index)"
            book.formats = templateBook.formats
            let readerInfo = ReaderInfo(
                deviceName: mockAppContainer.deviceName,
                url: URL(fileURLWithPath: "/tmp/reader-\(index).epub"),
                missing: false,
                format: .EPUB,
                readerType: .YabrEPUB,
                position: TestFixtures.makeReadingPosition(
                    id: mockAppContainer.deviceName,
                    readerName: ReaderType.YabrEPUB.rawValue,
                    lastReadPage: index + 1,
                    epoch: Double(index + 1)
                )
            )
            return mockAppContainer.openReader(
                book: book,
                readerInfo: readerInfo,
                source: .shelf,
                placement: .registryOnly
            )
        }
    }

    private func observeUnmountReason(
        from stream: AsyncStream<ReaderPresentationLifecycleEvent>,
        expectation: XCTestExpectation,
        reason: UnmountReasonBox
    ) -> Task<Void, Never> {
        Task { @MainActor in
            var iterator = stream.makeAsyncIterator()
            while let event = await iterator.next() {
                guard case let .unmount(unmountReason) = event else { continue }
                reason.value = unmountReason
                expectation.fulfill()
                return
            }
        }
    }
}

@MainActor
private final class UnmountReasonBox {
    var value: ReaderPresentationUnmountReason?
}
