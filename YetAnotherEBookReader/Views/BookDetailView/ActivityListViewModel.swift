//
//  ActivityListViewModel.swift
//  YetAnotherEBookReader
//
//  Created by京太郎 on 2026/06/06.
//

import Foundation
import SwiftUI

@MainActor
final class ActivityListViewModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var activities: [ActivityLogSnapshot] = []
    
    private var activitiesTask: Task<Void, Never>?
    private let libraryId: String?
    private let bookId: Int32?
    private let activityLogRepository: ActivityLogRepositoryProtocol
    
    init(repository: ActivityLogRepositoryProtocol, libraryId: String? = nil, bookId: Int32? = nil) {
        self.libraryId = libraryId
        self.bookId = bookId
        self.activityLogRepository = repository
    }

    deinit {
        activitiesTask?.cancel()
    }
    
    func start() {
        guard activitiesTask == nil else { return }
        let cutoff = Date(timeIntervalSinceNow: -86400 * 7)  // Show last 7 days
        activities = activityLogRepository.fetchEntries(libraryId: libraryId, bookId: bookId, since: cutoff)
        let activityUpdates = activityLogRepository.observeEntries(libraryId: libraryId, bookId: bookId, since: cutoff)
        activitiesTask = Task { @MainActor [weak self] in
            for await entries in activityUpdates {
                guard !Task.isCancelled else { break }
                self?.activities = entries
            }
        }
    }
    func stop() {
        activitiesTask?.cancel()
        activitiesTask = nil
    }

}
