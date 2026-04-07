import Foundation
import Combine
import RealmSwift

class CalibreActivityLogger {
    private let activityDispatchQueue = DispatchQueue(label: "io.github.dsreader.activity")
    private let logCalibreActivitySubject = PassthroughSubject<CalibreActivity, Never>()
    private var calibreCancellables = Set<AnyCancellable>()
    private let realmConf: Realm.Configuration
    
    init(realmConf: Realm.Configuration) {
        self.realmConf = realmConf
        registerLogCalibreActivityCancellable()
    }
    
    func logStartCalibreActivity(type: String, request: URLRequest, startDatetime: Date, bookId: Int32?, libraryId: String?) {
        logCalibreActivitySubject.send(
            CalibreActivityStart(type, request, startDatetime: startDatetime, bookId: bookId, libraryId: libraryId)
        )
    }
    
    func logFinishCalibreActivity(type: String, request: URLRequest, startDatetime: Date, finishDatetime: Date, errMsg: String) {
        logCalibreActivitySubject.send(
            CalibreActivityFinish(type, request, startDatetime: startDatetime, finishDatetime: finishDatetime, errMsg: errMsg)
        )
    }
    
    func removeCalibreActivity(obj: CalibreActivityLogEntry) {
        guard let realm = try? Realm(configuration: self.realmConf) else { return }

        try? realm.write {
            realm.delete(obj)
        }
    }

    func listCalibreActivities(libraryId: String? = nil, bookId: Int32? = nil, startDatetime: Date = Date(timeIntervalSinceNow: TimeInterval(-86400))) -> [CalibreActivityLogEntry] {
        guard let realm = try? Realm(configuration: self.realmConf) else { return [] }

        var pred = NSPredicate()
        if let libraryId = libraryId {
            if let bookId = bookId {
                pred = NSPredicate(
                    format: "startDatetime >= %@ AND libraryId = %@ AND bookId = %@",
                    Date(timeIntervalSinceNow: TimeInterval(86400) * -1) as NSDate,
                    libraryId,
                    NSNumber(value: bookId)
                )
            } else {
                pred = NSPredicate(
                    format: "startDatetime >= %@ AND libraryId = %@",
                    Date(timeIntervalSinceNow: TimeInterval(86400) * -1) as NSDate,
                    libraryId
                )
            }
        } else {
            pred = NSPredicate(
                format: "startDatetime > %@",
                Date(timeIntervalSinceNow: TimeInterval(86400) * -1) as NSDate
            )
        }

        let activities = realm.objects(CalibreActivityLogEntry.self).filter(pred)

        return activities.map { $0 }.sorted { $1.startDatetime < $0.startDatetime }
    }

    func cleanCalibreActivities(startDatetime: Date) {
        guard let realm = try? Realm(configuration: self.realmConf) else { return }
        
        let activities = realm.objects(CalibreActivityLogEntry.self).filter(
            NSPredicate(
                format: "startDatetime < %@",
                startDatetime as NSDate
            )
        )
        try? realm.write {
            realm.delete(activities)
        }
    }
    
    private func registerLogCalibreActivityCancellable() {
        logCalibreActivitySubject.collect(.byTimeOrCount(RunLoop.main, .seconds(1), 16))
            .receive(on: activityDispatchQueue)
            .sink { [weak self] activities in
                guard let self = self, let realm = try? Realm(configuration: self.realmConf) else { return }
                
                try? realm.write {
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
            .store(in: &calibreCancellables)
    }
}
