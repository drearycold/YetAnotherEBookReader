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
