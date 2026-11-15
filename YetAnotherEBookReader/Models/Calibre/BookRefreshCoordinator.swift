import Foundation
import OSLog

/// In-memory ownership of remote refreshes and their follow-up writes.
@MainActor
final class BookRefreshCoordinator {
    private static let maxOperations = 16
    private static let maxConcurrentUploads = 4
    private static let maxPendingRequests = 800

    enum Intent: Sendable { case caller, shelf }

    struct State: Sendable {
        let id: UUID
        let libraryID: String
        let intent: Intent
        var refreshing = true
        var waitingForCapacity = false
        var waitingToRetry = false
        var retries = 0
        var metadata: [Int32: BookMetadataRefreshResult] = [:]
        var annotationReads = 0
        var annotationFailures = 0
        var localMerges = 0
        var localMergeFailures = 0
        var localMergeSkips = 0
        var pendingUploads = 0
        var uploaded = 0
        var rejected = 0
        var uncertain = 0
        var discarded = 0
        var cancelled = false
        var superseded = false
    }

    enum Delivery: Sendable {
        case uploaded, rejected, uncertain, discarded
        // A lost transport may still be finishing the write on the server.
        case uncertainTransport
    }

    struct Upload {
        let lane: UploadLane
        let count: Int
        let readSequence: UInt64
        let deliver: @MainActor (CacheLibraryLifetime) async -> [Delivery]
    }

    struct UploadLane: Hashable {
        let serverID: String
        let libraryKey: String
        let bookID: Int32
    }

    private struct Operation {
        let scope: BookMetadataRefreshScope
        let deliveryLifetime = CacheLibraryLifetime()
        var state: State
        var refresh: Task<[Int32: BookMetadataRefreshResult], Never>?
    }

    private struct PendingUpload {
        let owner: UUID
        let upload: Upload
    }

    typealias Refresh = @MainActor (UUID, BookMetadataRefreshScope, [Int32]) async -> [Int32: BookMetadataRefreshResult]

    private struct ShelfRefresh {
        var state: State
        var scope: BookMetadataRefreshScope
        let work: Refresh
    }

    private let changes = ManagerAsyncBroadcaster<State>()
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "BookRefreshCoordinator")
    private var operations: [UUID: Operation] = [:]
    private var waitingShelfRefreshes: [ShelfRefresh] = []
    private var pending: [PendingUpload] = []
    private var running: [UploadLane: Task<Void, Never>] = [:]
    private var observers: [Task<Void, Never>] = []
    private let database: DatabaseService
    private let updateBusy: @MainActor (String, Bool) -> Void
    private let isShelved: @MainActor (CalibreLibrary, Int32) -> Bool
    private var uploadSequence: UInt64 = 0
    private var ambiguousThrough: [UploadLane: UInt64] = [:]

    init(database: DatabaseService, isShelved: @escaping @MainActor (CalibreLibrary, Int32) -> Bool,
         updateBusy: @escaping @MainActor (String, Bool) -> Void) {
        self.database = database
        self.isShelved = isShelved
        self.updateBusy = updateBusy
    }

    deinit {
        operations.values.forEach { $0.refresh?.cancel() }
        running.values.forEach { $0.cancel() }
        observers.forEach { $0.cancel() }
        changes.finish()
    }

    func updates() -> AsyncStream<State> {
        changes.stream(bufferingPolicy: .bufferingNewest(128))
    }

    func observe(libraries: AsyncStream<[String: CalibreLibrary]>) {
        guard observers.isEmpty else { return }
        let databaseChanges = database.cacheConfigurationChanges()
        observers = [
            Task { [weak self] in
                for await _ in databaseChanges { self?.advanceShelfRefreshes() }
            },
            Task { [weak self] in
                for await _ in libraries { self?.advanceShelfRefreshes() }
            }
        ]
    }

    func start(scope: BookMetadataRefreshScope, ids: [Int32], work: @escaping Refresh)
        -> Task<[Int32: BookMetadataRefreshResult], Never>? {
        advanceShelfRefreshes()
        guard operations.count < Self.maxOperations else { return nil }
        return admit(State(id: UUID(), libraryID: scope.library.id, intent: .caller), scope: scope, ids: ids, work: work)
    }

    func scheduleShelf(scope: BookMetadataRefreshScope, work: @escaping Refresh) {
        // A library has at most its base and public URL in the queue. A book
        // appears once per pinned scope, even when events keep arriving.
        waitingShelfRefreshes.removeAll { waiting in
            guard waiting.scope.library.id == scope.library.id,
                  waiting.scope.libraryRowID != scope.libraryRowID else { return false }
            publishRetiredShelfRefresh(waiting, result: .superseded)
            return true
        }
        if let index = waitingShelfRefreshes.firstIndex(where: {
            $0.scope.library.id == scope.library.id && $0.scope.database.id == scope.database.id
                && $0.scope.lifetime === scope.lifetime && $0.scope.source == scope.source
        }) {
            let shelf = waitingShelfRefreshes[index]
            let books = shelf.scope.books.filter { isShelved(scope.library, $0.key) }
                .merging(scope.books) { _, newest in newest }
            waitingShelfRefreshes[index].scope = scope.replacingBooks(books)
        } else {
            guard !scope.books.isEmpty else { return }
            var state = State(id: UUID(), libraryID: scope.library.id, intent: .shelf)
            state.waitingForCapacity = true
            waitingShelfRefreshes.append(.init(state: state, scope: scope, work: work))
            if operations.count >= Self.maxOperations { changes.send(state) }
        }
        advanceShelfRefreshes()
    }

    @discardableResult
    private func admit(_ state: State, scope: BookMetadataRefreshScope, ids: [Int32], work: @escaping Refresh)
        -> Task<[Int32: BookMetadataRefreshResult], Never> {
        let id = state.id
        let task = Task { [weak self] in
            let result = await work(id, scope, ids)
            self?.finishRefresh(id, result: result, cancelled: Task.isCancelled)
            return result
        }
        operations[id] = .init(scope: scope, state: state, refresh: task)
        updateBusy(scope.library.id, true)
        changes.send(state)
        return task
    }

    func record(_ id: UUID, _ update: (inout State) -> Void) {
        guard var operation = operations[id], !operation.state.superseded, !operation.state.cancelled else { return }
        update(&operation.state)
        operations[id] = operation
        changes.send(operation.state)
    }

    func enqueue(_ uploads: [Upload], for owner: UUID) {
        retireInvalid()
        guard let operation = operations[owner], !operation.state.superseded, !operation.state.cancelled else { return }
        var free = Self.maxPendingRequests - operations.values.reduce(0) { $0 + $1.state.pendingUploads }
        var accepted = 0
        var discarded = 0
        for upload in uploads {
            if upload.count <= free, upload.readSequence >= (ambiguousThrough[upload.lane] ?? 0) {
                pending.append(.init(owner: owner, upload: upload))
                free -= upload.count
                accepted += upload.count
            } else {
                discarded += upload.count
            }
        }
        record(owner) {
            $0.pendingUploads += accepted
            $0.discarded += discarded
        }
        pump()
    }

    /// Record when the annotation GET starts, so snapshots prepared before an
    /// ambiguous POST cannot be used to follow it.
    func beginAnnotationRead() -> UInt64 {
        uploadSequence
    }

    func cancelAll() {
        let waiting = waitingShelfRefreshes
        waitingShelfRefreshes.removeAll()
        for shelf in waiting { publishRetiredShelfRefresh(shelf, result: .cancelled) }
        for id in Array(operations.keys) { retire(id, superseded: false) }
    }

    private func advanceShelfRefreshes() {
        retireInvalid()
        while operations.count < Self.maxOperations, !waitingShelfRefreshes.isEmpty {
            var shelf = waitingShelfRefreshes.removeFirst()
            let ids = shelf.scope.books.keys.filter { isShelved(shelf.scope.library, $0) }.sorted()
            guard !ids.isEmpty else {
                publishRetiredShelfRefresh(shelf, result: .localBookMissing)
                continue
            }
            shelf.state.waitingForCapacity = false
            admit(shelf.state, scope: shelf.scope, ids: ids, work: shelf.work)
        }
    }

    private func publishRetiredShelfRefresh(_ refresh: ShelfRefresh, result: BookMetadataRefreshResult) {
        var state = refresh.state
        state.refreshing = false
        state.waitingForCapacity = false
        state.cancelled = result == .cancelled
        state.superseded = result == .superseded
        state.metadata = refresh.scope.books.mapValues { _ in result }
        changes.send(state)
    }

    private func retireInvalid() {
        waitingShelfRefreshes.removeAll { shelf in
            guard (try? shelf.scope.checkCurrent(in: database)) == nil else { return false }
            publishRetiredShelfRefresh(shelf, result: .superseded)
            return true
        }
        let retired = operations.compactMap { id, operation in
            (try? operation.scope.checkCurrent(in: database)) == nil ? id : nil
        }
        for id in retired { retire(id, superseded: true) }
    }

    private func retire(_ id: UUID, superseded: Bool) {
        guard var operation = operations[id], !operation.state.superseded, !operation.state.cancelled else { return }
        operation.state.superseded = superseded
        operation.state.cancelled = !superseded
        operation.state.waitingToRetry = false
        operation.deliveryLifetime.invalidate()
        let dropped = pending.filter { $0.owner == id }.reduce(0) { $0 + $1.upload.count }
        pending.removeAll { $0.owner == id }
        operation.state.pendingUploads -= dropped
        operation.state.discarded += dropped
        operations[id] = operation
        operation.refresh?.cancel()
        // Keep the book's lane until an already-dispatched POST settles. Its
        // server effect cannot be cancelled and newer writes must wait.
        publishAndClearIfFinished(id)
        refreshBusy(operation.state.libraryID)
    }

    private func finishRefresh(_ id: UUID, result: [Int32: BookMetadataRefreshResult], cancelled: Bool) {
        guard var operation = operations[id] else { return }
        operation.refresh = nil
        operation.state.refreshing = false
        operation.state.waitingToRetry = false
        operation.state.metadata = result
        if !operation.state.superseded { operation.state.cancelled = operation.state.cancelled || cancelled }
        operations[id] = operation
        publishAndClearIfFinished(id)
        advanceShelfRefreshes()
        refreshBusy(operation.state.libraryID)
    }

    private func refreshBusy(_ libraryID: String) {
        updateBusy(libraryID, operations.values.contains {
            $0.state.libraryID == libraryID && $0.state.refreshing && !$0.state.superseded
        })
    }

    private func publishAndClearIfFinished(_ id: UUID) {
        guard let state = operations[id]?.state else { return }
        changes.send(state)
        if !state.refreshing && state.pendingUploads == 0 {
            operations.removeValue(forKey: id)
            if operations.isEmpty { ambiguousThrough.removeAll() }
            if state.rejected + state.uncertain + state.discarded > 0 {
                logger.info("Refresh \(id) follow-ups: \(state.uploaded) uploaded, \(state.rejected) rejected, \(state.uncertain) uncertain, \(state.discarded) discarded")
            }
        }
    }

    private func pump() {
        while running.count < Self.maxConcurrentUploads,
              let index = pending.firstIndex(where: { running[$0.upload.lane] == nil }) {
            let next = pending.remove(at: index)
            let lane = next.upload.lane
            guard let lifetime = operations[next.owner]?.deliveryLifetime else { continue }
            let task = Task { [weak self] in
                let outcomes = await next.upload.deliver(lifetime)
                self?.finishUpload(next, outcomes: outcomes)
            }
            running[lane] = task
        }
    }

    private func finishUpload(_ pending: PendingUpload, outcomes: [Delivery]) {
        let lane = pending.upload.lane
        running.removeValue(forKey: lane)
        if var operation = operations[pending.owner] {
            operation.state.pendingUploads -= pending.upload.count
            for result in outcomes {
                switch result {
                case .uploaded: operation.state.uploaded += 1
                case .rejected: operation.state.rejected += 1
                case .uncertain, .uncertainTransport: operation.state.uncertain += 1
                case .discarded: operation.state.discarded += 1
                }
            }
            operations[pending.owner] = operation
            publishAndClearIfFinished(pending.owner)
        }
        if outcomes.contains(where: { outcome in
            if case .uncertainTransport = outcome { return true }
            return false
        }) {
            uploadSequence += 1
            ambiguousThrough[lane] = uploadSequence
            let stale = self.pending.filter { $0.upload.lane == lane }
            self.pending.removeAll { $0.upload.lane == lane }
            for item in stale {
                guard var owner = operations[item.owner] else { continue }
                owner.state.pendingUploads -= item.upload.count
                owner.state.discarded += item.upload.count
                operations[item.owner] = owner
                publishAndClearIfFinished(item.owner)
            }
        }
        if operations.isEmpty { ambiguousThrough.removeAll() }
        pump()
        advanceShelfRefreshes()
    }
}

private extension BookMetadataRefreshScope {
    func replacingBooks(_ books: [Int32: BookVersion]) -> Self {
        .init(library: library, source: source, database: database, lifetime: lifetime,
              libraryRowID: libraryRowID, books: books)
    }
}
