//
//  MainViewModel.swift
//  YetAnotherEBookReader
//
//  Created by opencode on 2026-06-18.
//

import SwiftUI
import Combine

@MainActor @available(macCatalyst 14.0, *)
final class MainViewModel: ObservableObject {
    private let container: AppContainer
    private let sessionManager: ReadingSessionManager
    private var cancellables = Set<AnyCancellable>()
    
    @Published var activeTab: Int = 0
    @Published var alertItem: AlertItem?
    @Published var initialTermsAgreementPresenting = false
    @Published var privacyWebViewPresenting = false
    @Published var termsWebViewPresenting = false
    @Published var bookImportActionSheetPresenting = false
    @Published var bookImportInfo: BookImportInfo?
    
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
    
    private func setupSubscriptions() {
        container.dismissAllSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.sessionManager.presentingEBookReaderFromShelf = false
            }
            .store(in: &cancellables)
            
        container.bookImportedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bookImportInfo in
                guard let self = self else { return }
                self.bookImportInfo = bookImportInfo
                self.handleImportedBook(bookImportInfo)
            }
            .store(in: &cancellables)
    }
    
    var showWelcome: Bool {
        activeTab < 1 && container.isDatabaseReady && container.bookManager.booksInShelf.isEmpty && container.bookManager.isShelfLoaded
    }

    var presentingEBookReaderFromShelf: Bool {
        get { sessionManager.presentingEBookReaderFromShelf }
        set { sessionManager.presentingEBookReaderFromShelf = newValue }
    }

    var readingBook: CalibreBook? {
        sessionManager.readingBook
    }

    var readerInfo: ReaderInfo? {
        sessionManager.readerInfo
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
        dismissAll { [weak self] in
            guard let self = self else { return }
            self.container.dismissAllSubject.send("")
            self.activeTab = 0
            self.bookImportActionSheetPresenting = false

            if let localLibrary = self.container.libraryManager.localLibrary,
               let bookId = info.bookId,
               let book = self.container.bookManager.booksInShelf[CalibreBook(id: bookId, library: localLibrary).inShelfId] {
                self.container.calibreUpdatedSubject.send(.book(book))
            }

            DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(250))) {
                self.bookImportActionSheetPresenting = true
            }
        }
    }

    func importBookAsNew(url: URL, bookId: Int32?) {
        let result = container.bookManager.onOpenURL(url: url, doMove: false, doOverwrite: false, asNew: true, knownBookId: bookId)
        container.bookImportedSubject.send(result)
    }

    func importBookOverwrite(url: URL, bookId: Int32?) {
        let result = container.bookManager.onOpenURL(url: url, doMove: false, doOverwrite: true, asNew: false, knownBookId: bookId)
        container.bookImportedSubject.send(result)
    }

    func openImportedBook() {
        guard let bookId = bookImportInfo?.bookId,
              let localLibrary = container.libraryManager.localLibrary else { return }
        let book = CalibreBook(id: bookId, library: localLibrary)
        container.bookManager.readingBookInShelfId = book.inShelfId
        guard sessionManager.readingBook != nil, sessionManager.readerInfo != nil else { return }
        sessionManager.presentingEBookReaderFromShelf = true
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
    
    func dismissAll(completion: @escaping () -> Void) {
        if let latest = container.presentingStack.last {
            if latest.wrappedValue == true {
                latest.wrappedValue = false
                DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(250))) { [weak self] in
                    self?.dismissAll(completion: completion)
                }
            } else {
                _ = container.presentingStack.popLast()
                dismissAll(completion: completion)
            }
        } else {
            completion()
        }
    }
}

@available(macCatalyst 14.0, *)
extension MainViewModel: AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}
