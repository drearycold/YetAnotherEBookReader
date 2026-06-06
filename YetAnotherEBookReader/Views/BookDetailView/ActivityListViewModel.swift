//
//  ActivityListViewModel.swift
//  YetAnotherEBookReader
//
//  Created by京太郎 on 2026/06/06.
//

import Foundation
import SwiftUI
import RealmSwift

struct ActivityLogUIEntry: Identifiable, Hashable {
    let id: String
    let libraryName: String
    let bookTitle: String
    let type: String
    let errMsg: String
    let startDateString: String
    let finishDateString: String
    let startDateLongString: String
    let finishDateLongString: String
    let endpointURL: String
    let httpMethod: String
    let httpBodyString: String?
}

class ActivityListViewModel: ObservableObject {
    @Published var activities: [ActivityLogUIEntry] = []
    
    private var notificationToken: NotificationToken?
    private let modelData: ModelData
    private let libraryId: String?
    private let bookId: Int32?
    
    init(modelData: ModelData, libraryId: String? = nil, bookId: Int32? = nil) {
        self.modelData = modelData
        self.libraryId = libraryId
        self.bookId = bookId
        
        loadActivities()
    }
    
    func loadActivities() {
        guard let realm = modelData.realmConf != nil ? try? Realm(configuration: modelData.realmConf!) : modelData.realm else { return }
        
        let cutoff = Date(timeIntervalSinceNow: -86400 * 7)  // Show last 7 days
        var predicate = NSPredicate(format: "startDatetime >= %@", cutoff as NSDate)
        
        if let libraryId = libraryId {
            if let bookId = bookId {
                predicate = NSPredicate(format: "startDatetime >= %@ AND libraryId == %@ AND bookId == %d", cutoff as NSDate, libraryId, bookId)
            } else {
                predicate = NSPredicate(format: "startDatetime >= %@ AND libraryId == %@", cutoff as NSDate, libraryId)
            }
        }
        
        let results = realm.objects(CalibreActivityLogEntry.self)
            .filter(predicate)
            .sorted(byKeyPath: "startDatetime", ascending: false)
        
        // Setup observation block to ensure list is updated reactively
        notificationToken = results.observe { [weak self] changes in
            guard let self = self else { return }
            switch changes {
            case .initial(let collection), .update(let collection, _, _, _):
                self.activities = collection.map { self.mapToUI($0) }
            case .error(let error):
                print("Realm observation error in ActivityListViewModel: \(error)")
            }
        }
    }
    
    private func mapToUI(_ obj: CalibreActivityLogEntry) -> ActivityLogUIEntry {
        var libraryName = "No Entity"
        var bookTitle = ""
        
        if let libraryId = obj.libraryId,
           let library = modelData.calibreLibraries[libraryId] {
            libraryName = library.name
            if let book = modelData.queryBookRealm(book: CalibreBook(id: obj.bookId, library: library), realm: modelData.realm) {
                bookTitle = book.title
            }
        }
        
        return ActivityLogUIEntry(
            id: obj.id,
            libraryName: libraryName,
            bookTitle: bookTitle,
            type: obj.type ?? "Unknown Type",
            errMsg: obj.errMsg ?? "Unknown Error",
            startDateString: obj.startDateByLocale ?? "Start Unknown",
            finishDateString: obj.finishDateByLocale ?? "Finish Unknown",
            startDateLongString: obj.startDateByLocaleLong ?? "Unknown",
            finishDateLongString: obj.finishDateByLocaleLong ?? "Unknown",
            endpointURL: obj.endpoingURL ?? "Unknown",
            httpMethod: obj.httpMethod ?? "GET",
            httpBodyString: {
                if let httpBody = obj.httpBody {
                    return String(data: httpBody, encoding: .utf8)
                }
                return nil
            }()
        )
    }
    
    deinit {
        notificationToken?.invalidate()
    }
}
