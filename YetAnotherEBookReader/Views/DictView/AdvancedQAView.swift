import SwiftUI
import UIKit
import FolioReaderKit

@MainActor
final class AdvancedQAViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded(AdvancedQAResponse)
        case failed(String)
    }

    @Published var query: String
    @Published var mode: AdvancedQAMode = .explain
    @Published var selectedScopeKind: String
    @Published var relatedByAuthor = true
    @Published var relatedByLibrary = false
    @Published var relatedByTag = false
    @Published var relatedCombine = "all"
    @Published var includeCurrentBook = false
    @Published var selectedBookIDs = ""
    @Published var selectedBooks = ""
    @Published private(set) var state: State = .idle

    private let context: ReaderSelectionContext
    private let candidates: [ReferenceCandidate]
    let retrievalScopes: AdvancedQARetrievalScopes
    private let queryHandler: (AdvancedQARequest) async throws -> AdvancedQAResponse

    init(context: ReaderSelectionContext,
         candidates: [ReferenceCandidate] = [],
         retrievalScopes: AdvancedQARetrievalScopes? = nil,
         queryHandler: @escaping (AdvancedQARequest) async throws -> AdvancedQAResponse) {
        self.context = context
        self.candidates = candidates
        self.query = ""
        let hasPosition = context.location.page != nil
        let resolvedScopes = retrievalScopes ?? .legacy(hasPosition: hasPosition)
        self.retrievalScopes = resolvedScopes
        let supported = Set(resolvedScopes.items.map(\.kind))
        let saved = UserDefaults.standard.string(forKey: "advancedQA.retrievalScope.kind")
        let preferred = saved.flatMap { supported.contains($0) ? $0 : nil }
        let defaultKind = supported.contains(resolvedScopes.defaultKind)
            ? resolvedScopes.defaultKind
            : resolvedScopes.items.first?.kind ?? "current_book"
        self.selectedScopeKind = preferred ?? defaultKind
        self.queryHandler = queryHandler
    }

    var selectedScope: AdvancedQARetrievalScopeCapability? {
        retrievalScopes.items.first { $0.kind == selectedScopeKind }
    }

    var canSubmit: Bool {
        guard let selectedScope,
              unavailableReason(for: selectedScope) == nil else { return false }
        if mode == .ask && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if selectedScope.kind == "related_books" {
            return relatedByAuthor || relatedByLibrary || relatedByTag
        }
        if selectedScope.kind == "selected_books" {
            let hasLocalID = selectedBookIDs.split(separator: ",").contains {
                Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            }
            return hasLocalID || parseSelectedBooks().isEmpty == false
        }
        return true
    }

    func unavailableReason(for scope: AdvancedQARetrievalScopeCapability) -> String? {
        let missing = scope.requires.filter { requirement in
            switch requirement {
            case "position": return context.location.page == nil
            case "series_metadata": return context.book.series?.isEmpty != false
            case "external_contexts": return candidates.isEmpty
            default: return false
            }
        }
        guard missing.isEmpty == false else { return nil }
        let names = missing.map {
            switch $0 {
            case "position": return "current reading position"
            case "series_metadata": return "book series metadata"
            case "external_contexts": return "reader annotations or references"
            default: return $0
            }
        }
        return "Requires " + names.joined(separator: ", ") + "."
    }

    private func makeScopeSelection() -> AdvancedQARetrievalScopeSelection {
        var selection = AdvancedQARetrievalScopeSelection(kind: selectedScopeKind)
        if selectedScopeKind == "related_books" {
            selection.relations = [
                relatedByAuthor ? .init(kind: "same_author") : nil,
                relatedByLibrary ? .init(kind: "same_library") : nil,
                relatedByTag ? .init(kind: "same_tag") : nil
            ].compactMap { $0 }
            selection.combine = relatedCombine
            selection.includeCurrentBook = includeCurrentBook
        } else if selectedScopeKind == "selected_books" {
            selection.bookIds = selectedBookIDs.split(separator: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            selection.books = parseSelectedBooks()
        }
        return selection
    }

    private func parseSelectedBooks() -> [AdvancedQARetrievalScopeSelection.BookReference] {
        selectedBooks.split(separator: ",").compactMap { entry in
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count >= 2, parts[0].isEmpty == false, let bookId = Int(parts[1]) else { return nil }
            let format = parts.count > 2 && parts[2].isEmpty == false ? parts[2].uppercased() : nil
            return .init(libraryId: parts[0], bookId: bookId, format: format)
        }
    }

    func submit() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selectedScope,
              unavailableReason(for: selectedScope) == nil else { return }
        guard mode != .ask || trimmed.isEmpty == false else { return }
        UserDefaults.standard.set(selectedScopeKind, forKey: "advancedQA.retrievalScope.kind")
        state = .loading
        do {
            state = .loaded(try await queryHandler(AdvancedQARequest(
                query: trimmed,
                mode: mode,
                readerContext: context,
                referenceCandidates: candidates,
                retrievalScope: makeScopeSelection()
            )))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct AdvancedQAView: View {
    @ObservedObject var viewModel: AdvancedQAViewModel

    var body: some View {
        Form {
            Section("Question") {
                TextField(
                    viewModel.mode == .ask ? "Ask about the selection" : "Optional instructions",
                    text: $viewModel.query
                )
                Picker("Mode", selection: $viewModel.mode) {
                    ForEach(AdvancedQAMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("Ask") { Task { await viewModel.submit() } }
                    .disabled(viewModel.canSubmit == false)
            }
            scopeSection
            result
        }
        .navigationTitle("Reader QA")
    }

    @ViewBuilder private var scopeSection: some View {
        Section("Retrieval Scope") {
            Picker("Search in", selection: $viewModel.selectedScopeKind) {
                ForEach(viewModel.retrievalScopes.items) { scope in
                    Text(scope.localizedLabel)
                        .tag(scope.kind)
                        .disabled(viewModel.unavailableReason(for: scope) != nil)
                }
            }
            if viewModel.retrievalScopes.isLegacy {
                Label("Legacy plugin scope fallback", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let scope = viewModel.selectedScope {
                Text(scope.localizedDescription).font(.caption)
                if let reason = viewModel.unavailableReason(for: scope) {
                    Text(reason).font(.caption).foregroundStyle(.red)
                }
                Label(scope.spoilerDescription,
                      systemImage: scope.spoilerSafe ? "shield.checkered" : "exclamationmark.shield")
                    .font(.caption)
                    .foregroundColor(scope.spoilerSafe ? .secondary : .orange)
                scopeParameters(scope)
            }
        }
    }

    @ViewBuilder private func scopeParameters(_ scope: AdvancedQARetrievalScopeCapability) -> some View {
        if scope.kind == "related_books" {
            if scope.parameters.contains("relations") {
                Toggle("Same author", isOn: $viewModel.relatedByAuthor)
                Toggle("Same library", isOn: $viewModel.relatedByLibrary)
                Toggle("Same tag", isOn: $viewModel.relatedByTag)
            }
            if scope.parameters.contains("combine") {
                Picker("Match relations", selection: $viewModel.relatedCombine) {
                    Text("All").tag("all")
                    Text("Any").tag("any")
                }
            }
            if scope.parameters.contains("include_current_book") {
                Toggle("Include current book", isOn: $viewModel.includeCurrentBook)
            }
        } else if scope.kind == "selected_books",
                  scope.parameters.contains("book_ids") || scope.parameters.contains("books") {
            if scope.parameters.contains("book_ids") {
                TextField("Current-library book IDs", text: $viewModel.selectedBookIDs)
                    .keyboardType(.numbersAndPunctuation)
            }
            if scope.parameters.contains("books") {
                TextField("library:book ID:format", text: $viewModel.selectedBooks)
                    .textInputAutocapitalization(.never)
                Text("Separate cross-library books with commas; format is optional.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var result: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .loading:
            Section { HStack { Spacer(); ProgressView(); Spacer() } }
        case .failed(let message):
            Section("Error") { Text(message).foregroundStyle(.red) }
        case .loaded(let response):
            Section("Answer") { Text(response.answer.text).textSelection(.enabled) }
            ForEach(response.cards) { card in
                Section(card.title) { Text(card.plainText ?? card.html ?? "") }
            }
            if response.evidence.isEmpty == false {
                Section("Evidence") {
                    ForEach(response.evidence) { evidence in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(evidence.title).font(.headline)
                            Text(evidence.content).font(.subheadline)
                        }
                    }
                }
            }
            if response.warnings.isEmpty == false {
                Section("Warnings") { ForEach(response.warnings, id: \.self, content: Text.init) }
            }
        }
    }
}

enum AdvancedQAConnectorFactory {
    static func helperConnector(for book: CalibreBook) -> DSReaderHelperConnector? {
        guard let container = AppContainer.shared,
              let helper = container.serverManager.queryServerDSReaderHelper(server: book.library.server) else { return nil }
        return DSReaderHelperConnector(
            calibreServerService: container.calibreServerService,
            server: book.library.server,
            dsreaderHelperServer: helper,
            goodreadsSync: nil
        )
    }

    @MainActor
    static func connector(for book: CalibreBook) -> DSReaderHelperConnector? {
        guard AppContainer.shared?.serverManager.queryServerDSReaderHelper(
            server: book.library.server
        )?.isAdvancedQAReady == true else { return nil }
        return helperConnector(for: book)
    }

    @MainActor static func navigationController(
        context: ReaderSelectionContext,
        candidates: [ReferenceCandidate] = [],
        retrievalScopes: AdvancedQARetrievalScopes? = nil,
        connector: DSReaderHelperConnector? = nil
    ) -> UINavigationController? {
        let resolvedConnector = connector ?? AppContainer.shared?.bookManager.booksInShelf
            .values.first(where: { $0.inShelfId == context.book.id })
            .flatMap(Self.connector(for:))
        guard let resolvedConnector else { return nil }
        let model = AdvancedQAViewModel(context: context, candidates: candidates,
                                        retrievalScopes: retrievalScopes) { request in
            try await resolvedConnector.queryAdvancedQA(request)
        }
        let host = UIHostingController(rootView: AdvancedQAView(viewModel: model))
        host.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak host] _ in host?.dismiss(animated: true) }
        )
        return UINavigationController(rootViewController: host)
    }
}

@MainActor
final class FolioAdvancedQAViewController: UIViewController {
    private let book: CalibreBook
    private let resolverProvider: () -> FolioReaderReferenceResolving?
    private var lastSelection: String?

    init(book: CalibreBook, resolverProvider: @escaping () -> FolioReaderReferenceResolving?) {
        self.book = book
        self.resolverProvider = resolverProvider
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let selection = navigationController?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              selection.isEmpty == false, selection != lastSelection else { return }
        lastSelection = selection
        Task { await load(selection: selection) }
    }

    private func load(selection: String) async {
        guard let connector = AdvancedQAConnectorFactory.connector(for: book) else { return }
        let lookup = await AdvancedQAContextBuilder.folioLookup(
            book: book,
            selection: selection,
            resolver: resolverProvider()
        )
        let scopes = AppContainer.shared?.serverManager.queryServerDSReaderHelper(
            server: book.library.server
        )?.advancedQAStatus?.retrievalScopes
        let model = AdvancedQAViewModel(context: lookup.context, candidates: lookup.candidates,
                                        retrievalScopes: scopes) { request in
            try await connector.queryAdvancedQA(request)
        }
        let host = UIHostingController(rootView: AdvancedQAView(viewModel: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
