//
//  MainViewModel.swift
//  YetAnotherEBookReader
//
//  Created by opencode on 2026-06-18.
//

import SwiftUI

@MainActor @available(macCatalyst 14.0, *)
final class MainViewModel: ObservableObject {
    private let container: AppContainer
    private let sessionManager: ReadingSessionManager
    private var bookImportTask: Task<Void, Never>?
    private var readerPresentationTask: Task<Void, Never>?
    private var readerPresentationListTask: Task<Void, Never>?
    
    @Published var activeTab: Int = 0
    @Published var alertItem: AlertItem?
    @Published var initialTermsAgreementPresenting = false
    @Published var privacyWebViewPresenting = false
    @Published var termsWebViewPresenting = false
    @Published var bookImportActionSheetPresenting = false
    @Published var bookImportInfo: BookImportInfo?
    @Published var readerPresentations: [ReaderPresentation] = []
    @Published var activeReaderPresentation: ReaderPresentation?
    
    // Reactive triggers for UI-level side effects (consent and URL opening)
    @Published var consentRequestTriggered = false
    @Published var urlToOpen: URL?
    
    let recentShelfViewModel: RecentShelfViewModel
    let sectionShelfViewModel: SectionShelfViewModel
    let settingsViewModel: SettingsViewModel
    
    init(container: AppContainer, sessionManager: ReadingSessionManager) {
        self.container = container
        self.sessionManager = sessionManager
        self.recentShelfViewModel = RecentShelfViewModel(container: container)
        self.sectionShelfViewModel = SectionShelfViewModel(container: container)
        self.settingsViewModel = SettingsViewModel(container: container)
        
        setupSubscriptions()
    }

    deinit {
        bookImportTask?.cancel()
        readerPresentationTask?.cancel()
        readerPresentationListTask?.cancel()
    }
    
    private func setupSubscriptions() {
        bookImportTask?.cancel()
        let bookImportEvents = container.bookImportEvents()
        bookImportTask = Task { @MainActor [weak self] in
            for await bookImportInfo in bookImportEvents {
                guard !Task.isCancelled, let self else { return }
                self.bookImportInfo = bookImportInfo
                self.handleImportedBook(bookImportInfo)
            }
        }

        readerPresentationTask?.cancel()
        let readerPresentationSnapshots = sessionManager.activeReaderPresentationSnapshots()
        readerPresentationTask = Task { @MainActor [weak self] in
            for await presentation in readerPresentationSnapshots {
                guard !Task.isCancelled else { return }
                self?.activeReaderPresentation = presentation
            }
        }

        readerPresentationListTask?.cancel()
        let readerPresentationListSnapshots = sessionManager.readerPresentationSnapshots()
        readerPresentationListTask = Task { @MainActor [weak self] in
            for await presentations in readerPresentationListSnapshots {
                guard !Task.isCancelled else { return }
                self?.readerPresentations = presentations
            }
        }
    }
    
    var showWelcome: Bool {
        activeTab < 1 && container.isDatabaseReady && container.bookManager.booksInShelf.isEmpty && container.bookManager.isShelfLoaded
    }
    
    func onAppear() {
        let termsAccepted = UserDefaults.standard.bool(forKey: Constants.KEY_DEFAULTS_INITIAL_TERMS_ACCEPTED)
        if !termsAccepted {
            initialTermsAgreementPresenting = true
        } else {
            consentRequestTriggered = true
        }
    }
    
    func acceptTerms() {
        UserDefaults.standard.setValue(true, forKey: Constants.KEY_DEFAULTS_INITIAL_TERMS_ACCEPTED)
        initialTermsAgreementPresenting = false
    }
    
    func declineTerms() {
        UserDefaults.standard.setValue(false, forKey: Constants.KEY_DEFAULTS_INITIAL_TERMS_ACCEPTED)
        exit(1)
    }
    
    func handleImportedBook(_ info: BookImportInfo) {
        activeTab = 0
        bookImportActionSheetPresenting = false

        if let localLibrary = container.libraryManager.localLibrary,
           let bookId = info.bookId,
           let book = container.bookManager.booksInShelf[CalibreBook(id: bookId, library: localLibrary).inShelfId] {
            container.publishCalibreUpdate(.book(book))
        }

        bookImportActionSheetPresenting = true
    }

    func importBookAsNew(url: URL, bookId: Int32?) {
        let result = container.bookManager.onOpenURL(url: url, doMove: false, doOverwrite: false, asNew: true, knownBookId: bookId)
        container.publishBookImport(result)
    }

    func importBookOverwrite(url: URL, bookId: Int32?) {
        let result = container.bookManager.onOpenURL(url: url, doMove: false, doOverwrite: true, asNew: false, knownBookId: bookId)
        container.publishBookImport(result)
    }

    func openImportedBook() {
        guard let bookId = bookImportInfo?.bookId,
              let localLibrary = container.libraryManager.localLibrary else { return }
        let book = CalibreBook(id: bookId, library: localLibrary)
        guard let importedBook = container.bookManager.booksInShelf[book.inShelfId] ?? container.bookRepository.getBook(id: book.inShelfId) else { return }
        let readerInfo = sessionManager.prepareBookReading(book: importedBook)
        guard readerInfo.missing == false else { return }
        sessionManager.openReader(book: importedBook, readerInfo: readerInfo, source: .importResult)
    }

    func reportImportError() {
        let issueURL = "https://github.com/drearycold/YetAnotherEBookReader/issues/new?labels=bug&assignees=drearycold"
        let errorStr = bookImportInfo?.error != nil ? String(describing: bookImportInfo?.error) : "Empty+Result"
        if let url = URL(string: issueURL + "&title=Error+Importing+Book+\(errorStr)&body=") {
            urlToOpen = url
        }
    }

    func updateCurrentPosition() {
        container.sessionManager.updateCurrentPosition(alertDelegate: self)
    }

    func closeReader(_ presentation: ReaderPresentation) {
        sessionManager.closeReader(id: presentation.id)
    }

    func closeActiveReader() {
        guard let activeReaderPresentation else { return }
        closeReader(activeReaderPresentation)
    }

    func activateReader(_ presentation: ReaderPresentation) {
        sessionManager.activateReader(id: presentation.id)
    }
}

@available(macCatalyst 14.0, *)
extension MainViewModel: AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}
