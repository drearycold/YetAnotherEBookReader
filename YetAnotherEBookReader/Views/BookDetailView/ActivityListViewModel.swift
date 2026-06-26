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
    
    private var activitiesCancellable: AnyCancellable?
    private let libraryId: String?
    private let bookId: Int32?
    private let activityLogRepository: ActivityLogRepositoryProtocol
    
    init(
        modelData: ModelData,
        libraryId: String? = nil,
        bookId: Int32? = nil,
        activityLogRepository: ActivityLogRepositoryProtocol? = nil
    ) {
        self.libraryId = libraryId
        self.bookId = bookId
        self.activityLogRepository = activityLogRepository ?? modelData.activityLogRepository
        
        loadActivities()
    }
    
    func loadActivities() {
        let cutoff = Date(timeIntervalSinceNow: -86400 * 7)  // Show last 7 days
        activities = activityLogRepository.fetchEntries(libraryId: libraryId, bookId: bookId, since: cutoff)
        activitiesCancellable = activityLogRepository
            .observeEntries(libraryId: libraryId, bookId: bookId, since: cutoff)
            .sink { [weak self] in
                self?.activities = $0
            }
    }
}
