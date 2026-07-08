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
    let readerWorkspaceViewModel: ReaderWorkspaceViewModel
    
    init(container: AppContainer, sessionManager: ReadingSessionManager) {
        self.container = container
        self.sessionManager = sessionManager
        self.recentShelfViewModel = RecentShelfViewModel(container: container)
        self.sectionShelfViewModel = SectionShelfViewModel(container: container)
        self.settingsViewModel = SettingsViewModel(container: container)
        self.readerWorkspaceViewModel = ReaderWorkspaceViewModel(container: container)
        
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
        container.openReader(book: importedBook, readerInfo: readerInfo, source: .importResult)
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

    func handleScenePhase(_ scenePhase: ScenePhase) {
        readerWorkspaceViewModel.handleScenePhase(scenePhase)
    }

    func handleReaderSceneActivity(_ activity: NSUserActivity) {
        guard let presentationID = ReaderSceneActivity.presentationID(from: activity) else { return }
        readerWorkspaceViewModel.attachPresentation(id: presentationID)
    }
}

@available(macCatalyst 14.0, *)
extension MainViewModel: AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}

@MainActor @available(macCatalyst 14.0, *)
final class ReaderWorkspaceViewModel: ObservableObject {
    let id = UUID()

    private let container: AppContainer
    private var registryTask: Task<Void, Never>?
    private var openRequestTask: Task<Void, Never>?
    private let lifecycleBroadcaster = ManagerAsyncBroadcaster<ScenePhase>()

    @Published private(set) var presentationIDs: [ReaderPresentation.ID] = []
    @Published private(set) var presentationsByID: [ReaderPresentation.ID: ReaderPresentation] = [:]
    @Published var activePresentationID: ReaderPresentation.ID?
    @Published var isPresented = false

    init(container: AppContainer) {
        self.container = container
        setupTasks()
    }

    deinit {
        registryTask?.cancel()
        openRequestTask?.cancel()
        lifecycleBroadcaster.finish()
    }

    var hasReaders: Bool {
        presentationIDs.isEmpty == false
    }

    var presentations: [ReaderPresentation] {
        presentationIDs.compactMap { presentationsByID[$0] }
    }

    var activePresentation: ReaderPresentation? {
        guard let activePresentationID else { return nil }
        return presentationsByID[activePresentationID]
    }

    var supportsReaderWindows: Bool {
        container.supportsReaderWindows
    }

    func readerLifecycleEvents() -> AsyncStream<ScenePhase> {
        lifecycleBroadcaster.stream()
    }

    func attachPresentation(id presentationID: ReaderPresentation.ID) {
        guard container.sessionManager.readerPresentation(id: presentationID) != nil else { return }
        if presentationIDs.contains(presentationID) == false {
            presentationIDs.append(presentationID)
        }
        activatePresentation(id: presentationID)
        isPresented = true
    }

    func activatePresentation(id presentationID: ReaderPresentation.ID) {
        guard presentationIDs.contains(presentationID) else { return }
        activePresentationID = presentationID
        container.sessionManager.activateReader(id: presentationID)
    }

    func closePresentation(id presentationID: ReaderPresentation.ID) {
        let wasActive = activePresentationID == presentationID
        presentationIDs.removeAll { $0 == presentationID }
        container.sessionManager.closeReader(id: presentationID)

        if wasActive {
            activePresentationID = presentationIDs.last
            if let activePresentationID {
                container.sessionManager.activateReader(id: activePresentationID)
            }
        }

        if presentationIDs.isEmpty {
            isPresented = false
        }
    }

    func closeActivePresentation() {
        guard let activePresentationID else { return }
        closePresentation(id: activePresentationID)
    }

    func showReader() {
        guard hasReaders else { return }
        isPresented = true
    }

    func hideReader() {
        isPresented = false
    }

    func openActivePresentationInNewWindow() {
        guard supportsReaderWindows, let activePresentation else { return }
        let newPresentation = container.openReader(
            book: activePresentation.book,
            readerInfo: activePresentation.readerInfo,
            source: activePresentation.source,
            placement: .registryOnly,
            reuseExisting: false
        )
        _ = container.requestReaderWindow(for: newPresentation)
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            container.setActiveReaderWorkspace(id: id)
        case .background:
            container.clearActiveReaderWorkspace(id: id)
        case .inactive:
            break
        @unknown default:
            break
        }
        lifecycleBroadcaster.send(scenePhase)
    }

    private func setupTasks() {
        let registrySnapshots = container.sessionManager.readerPresentationSnapshots()
        registryTask = Task { @MainActor [weak self] in
            for await presentations in registrySnapshots {
                guard !Task.isCancelled, let self else { return }
                self.presentationsByID = Dictionary(uniqueKeysWithValues: presentations.map { ($0.id, $0) })
                self.presentationIDs.removeAll { self.presentationsByID[$0] == nil }
                if let activePresentationID = self.activePresentationID,
                   self.presentationsByID[activePresentationID] == nil {
                    self.activePresentationID = self.presentationIDs.last
                }
                if self.presentationIDs.isEmpty {
                    self.isPresented = false
                }
            }
        }

        let openRequests = container.readerOpenRequests()
        openRequestTask = Task { @MainActor [weak self] in
            for await request in openRequests {
                guard !Task.isCancelled, let self else { return }
                guard request.targetWorkspaceID == nil || request.targetWorkspaceID == self.id else { continue }
                self.attachPresentation(id: request.presentationID)
            }
        }
    }
}
