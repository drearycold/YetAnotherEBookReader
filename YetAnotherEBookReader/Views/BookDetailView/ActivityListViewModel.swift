//
//  ActivityListViewModel.swift
//  YetAnotherEBookReader
//

import Foundation
import SwiftUI

@MainActor
final class ActivityListViewModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var page = ActivityLogPage()
    @Published var filter = ActivityLogFilter() {
        didSet {
            guard filter != oldValue else { return }
            limit = pageSize
            if observation == nil {
                page = ActivityLogPage()
            } else {
                restart()
            }
        }
    }

    private var observation: Task<Void, Never>?
    private var generation: UUID?
    private let libraryId: String?
    private let bookId: Int32?
    private let repository: ActivityLogRepositoryProtocol
    private let pageSize: Int
    private let now: () -> Date
    private var limit: Int

    init(repository: ActivityLogRepositoryProtocol, libraryId: String? = nil, bookId: Int32? = nil,
         pageSize: Int = 30, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.libraryId = libraryId
        self.bookId = bookId
        self.pageSize = max(1, pageSize)
        self.limit = max(1, pageSize)
        self.now = now
    }

    deinit {
        observation?.cancel()
    }

    func start() {
        guard observation == nil else { return }
        restart()
    }

    func stop() {
        observation?.cancel()
        observation = nil
        generation = nil
    }

    func refreshIfVisible() {
        guard observation != nil else { return }
        restart()
    }

    func loadMore() {
        guard observation != nil, page.hasMore else { return }
        limit += pageSize
        restart()
    }

    func makeDetailViewModel(id: ActivityID) -> ActivityDetailViewModel {
        ActivityDetailViewModel(id: id, repository: repository, bookId: bookId, now: now)
    }

    private func restart() {
        stop()
        let query = ActivityLogQuery(libraryId: libraryId, bookId: bookId,
                                     since: ActivityLogRetention.cutoff(at: now()), filter: filter)
        let generation = UUID()
        self.generation = generation
        let initial = repository.fetchPage(query: query, limit: limit)
        if page != initial { page = initial }
        let updates = repository.observePage(query: query, limit: limit)
        observation = Task { @MainActor [weak self] in
            for await page in updates {
                guard !Task.isCancelled, let self, self.generation == generation else { break }
                if self.page != page { self.page = page }
            }
        }
    }
}

@MainActor
final class ActivityDetailViewModel: ObservableObject {
    @Published private(set) var entry: ActivityLogSnapshot?

    let id: ActivityID
    private let repository: ActivityLogRepositoryProtocol
    private let bookId: Int32?
    private let now: () -> Date
    private var observation: Task<Void, Never>?
    private var generation: UUID?

    init(id: ActivityID, repository: ActivityLogRepositoryProtocol, bookId: Int32? = nil,
         now: @escaping () -> Date = Date.init) {
        self.id = id
        self.repository = repository
        self.bookId = bookId
        self.now = now
    }

    deinit {
        observation?.cancel()
    }

    func start() {
        guard observation == nil else { return }
        let since = ActivityLogRetention.cutoff(at: now())
        let generation = UUID()
        self.generation = generation
        entry = repository.fetchDetail(id: id, bookId: bookId, since: since)
        let updates = repository.observeDetail(id: id, bookId: bookId, since: since)
        observation = Task { @MainActor [weak self] in
            for await entry in updates {
                guard !Task.isCancelled, let self, self.generation == generation else { break }
                self.entry = entry
            }
        }
    }

    func stop() {
        observation?.cancel()
        observation = nil
        generation = nil
    }

    func refreshIfVisible() {
        guard observation != nil else { return }
        stop()
        start()
    }
}
