//
//  MainViewModel.swift
//  YetAnotherEBookReader
//
//  Created by opencode on 2026-06-18.
//

import SwiftUI

enum ReaderPresentationUnmountReason: Equatable {
    case close
    case temporary
    case transfer
}

enum ReaderPresentationLifecycleEvent {
    case activated
    case deactivated
    case scenePhase(ScenePhase)
    case unmount(ReaderPresentationUnmountReason)
}

@MainActor @available(macCatalyst 14.0, *)
final class MainViewModel: ObservableObject {
    private let container: AppContainer
    private let sessionManager: ReadingSessionManager
    private var bookImportTask: Task<Void, Never>?
    private var readerPresentationTask: Task<Void, Never>?
    private var readerPresentationListTask: Task<Void, Never>?
    private var welcomeBooksInShelfTask: Task<Void, Never>?
    private var welcomeShelfLoadedTask: Task<Void, Never>?
    
    @Published var activeTab: Int = 0
    @Published var alertItem: AlertItem?
    @Published var initialTermsAgreementPresenting = false
    @Published var privacyWebViewPresenting = false
    @Published var termsWebViewPresenting = false
    @Published var bookImportActionSheetPresenting = false
    @Published var bookImportInfo: BookImportInfo?
    @Published var readerPresentations: [ReaderPresentation] = []
    @Published var activeReaderPresentation: ReaderPresentation?
    @Published private(set) var welcomeShelfStateVersion = 0
    
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
        let readerWorkspaceViewModel = ReaderWorkspaceViewModel(container: container)
        self.readerWorkspaceViewModel = readerWorkspaceViewModel
        self.recentShelfViewModel = RecentShelfViewModel(
            container: container,
            targetWorkspaceID: readerWorkspaceViewModel.id
        )
        self.sectionShelfViewModel = SectionShelfViewModel(container: container)
        self.settingsViewModel = SettingsViewModel(container: container)
        
        setupSubscriptions()
    }

    deinit {
        bookImportTask?.cancel()
        readerPresentationTask?.cancel()
        readerPresentationListTask?.cancel()
        welcomeBooksInShelfTask?.cancel()
        welcomeShelfLoadedTask?.cancel()
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

        welcomeBooksInShelfTask?.cancel()
        let booksInShelfSnapshots = container.bookManager.booksInShelfSnapshots()
        welcomeBooksInShelfTask = Task { @MainActor [weak self] in
            for await _ in booksInShelfSnapshots {
                guard !Task.isCancelled else { return }
                self?.welcomeShelfStateVersion += 1
            }
        }

        welcomeShelfLoadedTask?.cancel()
        let shelfLoadedSnapshots = container.bookManager.isShelfLoadedSnapshots()
        welcomeShelfLoadedTask = Task { @MainActor [weak self] in
            for await _ in shelfLoadedSnapshots {
                guard !Task.isCancelled else { return }
                self?.welcomeShelfStateVersion += 1
            }
        }
    }
    
    var showWelcome: Bool {
        activeTab < 1 && container.isDatabaseReady && container.bookManager.booksInShelf.isEmpty && container.bookManager.isShelfLoaded
    }

    func openWelcomeSettings() {
        activeTab = 3
    }

    func openWelcomeBrowse() {
        activeTab = 2
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
        container.openReader(
            book: importedBook,
            readerInfo: readerInfo,
            source: .importResult,
            targetWorkspaceID: readerWorkspaceViewModel.id
        )
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

    func restorePersistedReadersIfNeeded() {
        let restoredPresentations = sessionManager.restorePersistedReaderPresentationsIfNeeded()
        guard restoredPresentations.isEmpty == false else { return }
        let restoredActivePresentationID = sessionManager.activeReaderPresentationID

        restoredPresentations.forEach { presentation in
            readerWorkspaceViewModel.attachPresentation(id: presentation.id)
        }
        if let activePresentationID = restoredActivePresentationID {
            readerWorkspaceViewModel.activatePresentation(id: activePresentationID)
        }
        activeReaderPresentation = sessionManager.activeReaderPresentation
        readerWorkspaceViewModel.showReader()
    }

    func handleReaderSceneActivity(_ activity: NSUserActivity) {
        guard let presentationID = ReaderSceneActivity.presentationID(from: activity) else { return }
        readerWorkspaceViewModel.attachPresentation(id: presentationID, completesTransfer: true)
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

    private let mountedPresentationLimit = 3
    private let container: AppContainer
    private var registryTask: Task<Void, Never>?
    private var openRequestTask: Task<Void, Never>?
    private var transferTask: Task<Void, Never>?
    private var lifecycleBroadcasters = [ReaderPresentation.ID: ManagerAsyncBroadcaster<ReaderPresentationLifecycleEvent>]()

    @Published private(set) var presentationIDs: [ReaderPresentation.ID] = []
    @Published private(set) var presentationsByID: [ReaderPresentation.ID: ReaderPresentation] = [:]
    @Published private(set) var mountedPresentationIDs: [ReaderPresentation.ID] = []
    @Published var activePresentationID: ReaderPresentation.ID?
    @Published var isPresented = false

    init(container: AppContainer) {
        self.container = container
        setupTasks()
    }

    deinit {
        registryTask?.cancel()
        openRequestTask?.cancel()
        transferTask?.cancel()
        lifecycleBroadcasters.values.forEach { $0.finish() }
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

    var mountedPresentations: [ReaderPresentation] {
        mountedPresentationIDs.compactMap { presentationsByID[$0] }
    }

    var supportsReaderWindows: Bool {
        container.supportsReaderWindows
    }

    func readerLifecycleEvents(for presentationID: ReaderPresentation.ID) -> AsyncStream<ReaderPresentationLifecycleEvent> {
        let broadcaster = lifecycleBroadcaster(for: presentationID)
        let initialEvent: ReaderPresentationLifecycleEvent = activePresentationID == presentationID && isPresented ? .activated : .deactivated
        return broadcaster.stream(initialValue: initialEvent)
    }

    func attachPresentation(id presentationID: ReaderPresentation.ID, completesTransfer: Bool = false) {
        guard let presentation = container.sessionManager.readerPresentationForMount(id: presentationID) else { return }
        presentationsByID[presentationID] = presentation
        if presentationIDs.contains(presentationID) == false {
            presentationIDs.append(presentationID)
        }
        isPresented = true
        activatePresentation(id: presentationID)
        if completesTransfer {
            container.publishReaderPresentationTransfer(presentationID: presentationID, targetWorkspaceID: id)
        }
    }

    func activatePresentation(id presentationID: ReaderPresentation.ID) {
        guard presentationIDs.contains(presentationID) else { return }
        let previousActivePresentationID = activePresentationID
        if let presentation = container.sessionManager.readerPresentationForMount(id: presentationID) {
            presentationsByID[presentationID] = presentation
        }
        if previousActivePresentationID != presentationID,
           let previousActivePresentationID {
            lifecycleBroadcaster(for: previousActivePresentationID).send(.deactivated)
        }
        activePresentationID = presentationID
        mountPresentation(id: presentationID)
        container.sessionManager.activateReader(id: presentationID)
        if isPresented {
            lifecycleBroadcaster(for: presentationID).send(.activated)
        }
    }

    func closePresentation(id presentationID: ReaderPresentation.ID) {
        let wasActive = activePresentationID == presentationID
        sendUnmount(.close, for: presentationID)
        presentationIDs.removeAll { $0 == presentationID }
        mountedPresentationIDs.removeAll { $0 == presentationID }
        container.sessionManager.closeReader(id: presentationID)

        if wasActive {
            activePresentationID = nil
            if let nextActivePresentationID = presentationIDs.last {
                activatePresentation(id: nextActivePresentationID)
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
        if let activePresentationID {
            lifecycleBroadcaster(for: activePresentationID).send(.activated)
        }
    }

    func hideReader() {
        if let activePresentationID {
            lifecycleBroadcaster(for: activePresentationID).send(.deactivated)
        }
        isPresented = false
    }

    func openEmptyReaderWindow() {
        guard supportsReaderWindows else { return }
        _ = container.requestEmptyReaderWindow()
    }

    func moveActivePresentationToNewWindow() {
        guard supportsReaderWindows, let activePresentation else { return }
        guard container.requestReaderWindow(for: activePresentation) else { return }
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
        mountedPresentationIDs.forEach { presentationID in
            lifecycleBroadcaster(for: presentationID).send(.scenePhase(scenePhase))
        }
    }

    private func setupTasks() {
        let registrySnapshots = container.sessionManager.readerPresentationSnapshots()
        registryTask = Task { @MainActor [weak self] in
            for await _ in registrySnapshots {
                guard !Task.isCancelled, let self else { return }
                let presentations = self.container.sessionManager.readerPresentations
                let presentationMap = Dictionary(uniqueKeysWithValues: presentations.map { ($0.id, $0) })
                let removedPresentationIDs = self.presentationIDs.filter { presentationMap[$0] == nil }
                removedPresentationIDs.forEach { self.sendUnmount(.close, for: $0) }
                self.presentationsByID = Dictionary(uniqueKeysWithValues: presentations.map { ($0.id, $0) })
                self.presentationIDs.removeAll { self.presentationsByID[$0] == nil }
                self.mountedPresentationIDs.removeAll { self.presentationsByID[$0] == nil }
                if let activePresentationID = self.activePresentationID,
                   self.presentationsByID[activePresentationID] == nil {
                    self.activePresentationID = nil
                    if let nextActivePresentationID = self.presentationIDs.last {
                        self.activatePresentation(id: nextActivePresentationID)
                    }
                }
                if self.presentationIDs.isEmpty {
                    self.isPresented = false
                } else if let activePresentationID = self.activePresentationID {
                    self.mountPresentation(id: activePresentationID)
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

        let transferCompletions = container.readerPresentationTransfers()
        transferTask = Task { @MainActor [weak self] in
            for await transfer in transferCompletions {
                guard !Task.isCancelled, let self else { return }
                guard transfer.targetWorkspaceID != self.id else { continue }
                guard self.presentationIDs.contains(transfer.presentationID) else { continue }
                self.container.markReaderPresentationTransfer(id: transfer.presentationID)
                self.detachPresentation(id: transfer.presentationID, unmountReason: .transfer)
            }
        }
    }

    private func detachPresentation(id presentationID: ReaderPresentation.ID, unmountReason: ReaderPresentationUnmountReason) {
        let wasActive = activePresentationID == presentationID
        sendUnmount(unmountReason, for: presentationID)
        presentationIDs.removeAll { $0 == presentationID }
        mountedPresentationIDs.removeAll { $0 == presentationID }

        if wasActive {
            activePresentationID = nil
            if let nextActivePresentationID = presentationIDs.last {
                activatePresentation(id: nextActivePresentationID)
            }
        }

        if presentationIDs.isEmpty {
            activePresentationID = nil
            isPresented = false
        }
    }

    private func mountPresentation(id presentationID: ReaderPresentation.ID) {
        mountedPresentationIDs.removeAll { $0 == presentationID }
        mountedPresentationIDs.append(presentationID)
        trimMountedPresentations()
    }

    private func trimMountedPresentations() {
        while mountedPresentationIDs.count > mountedPresentationLimit,
              let presentationIDToUnmount = mountedPresentationIDs.first(where: { $0 != activePresentationID }) {
            sendUnmount(.temporary, for: presentationIDToUnmount)
            mountedPresentationIDs.removeAll { $0 == presentationIDToUnmount }
        }
    }

    private func sendUnmount(_ reason: ReaderPresentationUnmountReason, for presentationID: ReaderPresentation.ID) {
        guard mountedPresentationIDs.contains(presentationID) else { return }
        lifecycleBroadcaster(for: presentationID).send(.unmount(reason))
        if reason == .close {
            lifecycleBroadcasters.removeValue(forKey: presentationID)?.finish()
        }
    }

    private func lifecycleBroadcaster(for presentationID: ReaderPresentation.ID) -> ManagerAsyncBroadcaster<ReaderPresentationLifecycleEvent> {
        if let broadcaster = lifecycleBroadcasters[presentationID] {
            return broadcaster
        }
        let broadcaster = ManagerAsyncBroadcaster<ReaderPresentationLifecycleEvent>()
        lifecycleBroadcasters[presentationID] = broadcaster
        return broadcaster
    }
}
