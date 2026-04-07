import Foundation
import RealmSwift

actor CalibreActivityLogger {
    private let realmConf: Realm.Configuration
    private var pendingActivities: [CalibreActivity] = []
    private var flushTask: Task<Void, Never>?
    
    init(realmConf: Realm.Configuration) {
        self.realmConf = realmConf
    }
    
    func logStartCalibreActivity(type: String, request: URLRequest, startDatetime: Date, bookId: Int32?, libraryId: String?) {
        pendingActivities.append(
            CalibreActivityStart(type, request, startDatetime: startDatetime, bookId: bookId, libraryId: libraryId)
        )
        scheduleFlush()
    }
    
    func logFinishCalibreActivity(type: String, request: URLRequest, startDatetime: Date, finishDatetime: Date, errMsg: String) {
        pendingActivities.append(
            CalibreActivityFinish(type, request, startDatetime: startDatetime, finishDatetime: finishDatetime, errMsg: errMsg)
        )
        scheduleFlush()
    }
    
    private func scheduleFlush() {
        // If there's already a task waiting to flush, let it handle the new activity
        guard flushTask == nil else { return }
        
        flushTask = Task {
            // Wait for 1 second to batch activities, similar to Combine's collect
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await flush()
            flushTask = nil
        }
    }
    
    private func flush() async {
        let activities = pendingActivities
        pendingActivities.removeAll()

        guard !activities.isEmpty else { return }

        // Perform Realm write on actor's executor
        guard let realm = try? await Realm(configuration: self.realmConf, actor: self) else { return }

        try? await realm.asyncWrite {
            activities.forEach { activity in
                if let activityStart = activity as? CalibreActivityStart {
                    let obj = CalibreActivityLogEntry()

                    obj.type = activityStart.type

                    obj.startDatetime = activityStart.startDatetime
                    obj.bookId = activityStart.bookId ?? 0
                    obj.libraryId = activityStart.libraryId

                    obj.endpoingURL = activityStart.request.url?.absoluteString
                    obj.httpMethod = activityStart.request.httpMethod
                    obj.httpBody = activityStart.request.httpBody
                    activityStart.request.allHTTPHeaderFields?.forEach {
                        obj.requestHeaders.append($0.key)
                        obj.requestHeaders.append($0.value)
                    }

                    realm.add(obj)
                }

                if let activityFinish = activity as? CalibreActivityFinish {
                    guard let activityPrevious = realm.objects(CalibreActivityLogEntry.self).filter(
                        NSPredicate(format: "type = %@ AND startDatetime = %@ AND endpoingURL = %@",
                                    activityFinish.type,
                                    activityFinish.startDatetime as NSDate,
                                    activityFinish.request.url?.absoluteString ?? ""
                        )
                    ).first else { return }

                    activityPrevious.finishDatetime = activityFinish.finishDatetime
                    activityPrevious.errMsg = activityFinish.errMsg
                }
            }
        }
    }

    
    func removeCalibreActivity(id: String) async {
        guard let realm = try? await Realm(configuration: self.realmConf, actor: self) else { return }
        if let obj = realm.object(ofType: CalibreActivityLogEntry.self, forPrimaryKey: id) {
            try? await realm.asyncWrite {
                realm.delete(obj)
            }
        }
    }

    func cleanCalibreActivities(startDatetime: Date) async {
        guard let realm = try? await Realm(configuration: self.realmConf, actor: self) else { return }
        
        let activities = realm.objects(CalibreActivityLogEntry.self).filter(
            NSPredicate(
                format: "startDatetime < %@",
                startDatetime as NSDate
            )
        )
        try? await realm.asyncWrite {
            realm.delete(activities)
        }
    }
}
