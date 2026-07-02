//
//  ActivityListViewModel.swift
//  YetAnotherEBookReader
//
//  Created by京太郎 on 2026/06/06.
//

import Foundation
import SwiftUI
import Combine

class ActivityListViewModel: ObservableObject {
    @Published var activities: [ActivityLogUIEntry] = []
    
    private var activitiesTask: Task<Void, Never>?
    private let libraryId: String?
    private let bookId: Int32?
    private let activityLogRepository: ActivityLogRepositoryProtocol
    
    init(
        container: AppContainer,
        libraryId: String? = nil,
        bookId: Int32? = nil,
        activityLogRepository: ActivityLogRepositoryProtocol? = nil
    ) {
        self.libraryId = libraryId
        self.bookId = bookId
        self.activityLogRepository = activityLogRepository ?? container.activityLogRepository
        
        loadActivities()
    }

    deinit {
        activitiesTask?.cancel()
    }
    
    func loadActivities() {
        let cutoff = Date(timeIntervalSinceNow: -86400 * 7)  // Show last 7 days
        activities = activityLogRepository.fetchEntries(libraryId: libraryId, bookId: bookId, since: cutoff)
        activitiesTask?.cancel()
        let activityUpdates = activityLogRepository.observeEntries(libraryId: libraryId, bookId: bookId, since: cutoff)
        activitiesTask = Task { @MainActor [weak self] in
            for await entries in activityUpdates {
                guard !Task.isCancelled else { break }
                self?.activities = entries
            }
        }
    }
}
