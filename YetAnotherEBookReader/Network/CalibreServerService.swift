//
//  CalibreServerService.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/12.
//

import Foundation
import OSLog
import Combine

struct CalibreServerService {
    var modelData: ModelData

    var defaultLog = Logger()

    func urlSession(server: CalibreServer, timeout: Double = 600, qos: DispatchQoS.QoSClass = .default) -> URLSession {
        let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
        if let session = modelData.metadataSessions[key] {
            return session
        }
        let urlSessionConfiguration = URLSessionConfiguration.default
        urlSessionConfiguration.timeoutIntervalForRequest = timeout
        urlSessionConfiguration.httpMaximumConnectionsPerHost = 4
        let urlSessionDelegate = CalibreServerTaskDelegate(server)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: modelData.metadataQueue)
        
        if Thread.isMainThread {
            modelData.metadataSessions[key] = urlSession
        } else {
            DispatchQueue.main.sync {
                modelData.metadataSessions[key] = urlSession
            }
        }
        return urlSession
    }
    
    func syncLibraryPublisher(resultPrev: CalibreSyncLibraryResult, filter: String = "") -> AnyPublisher<CalibreSyncLibraryResult, Never> {
        guard let serverUrl = getServerUrlByReachability(server: resultPrev.request.library.server) else {
            var result = resultPrev
            result.errmsg = "Server not Reachable"
            return Just(result).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        guard var urlComponents = URLComponents(string: serverUrl.absoluteString) else {
            var result = resultPrev
            result.errmsg = "Internal Error"
            return Just(result).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        urlComponents.path.append("/cdb/cmd/list/0")
        urlComponents.queryItems = [URLQueryItem(name: "library_id", value: resultPrev.request.library.key)]
        
        guard let endpointUrl = urlComponents.url(relativeTo: serverUrl) else {
            var result = resultPrev
            result.errmsg = "Internal Error"
            return Just(result).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
//        let json:[Any] = [["title", "authors", "formats", "rating", "series", "series_index", "identifiers", "last_modified", "timestamp", "pubdate", "tags"], "last_modified", "ascending", filter, -1]
        let json:[Any] = [["last_modified"], "last_modified", "ascending", filter, -1]
        
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else {
            var result = resultPrev
            result.errmsg = "Query Error"
            return Just(result).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: endpointUrl)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = data
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.addValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        
        print("\(#function) listRequest \(endpointUrl.absoluteString) \(String(data: data, encoding: .utf8))")
        
        let startDatetime = Date()
        modelData.logStartCalibreActivity(type: "Sync Library Books", request: urlRequest, startDatetime: startDatetime, bookId: nil, libraryId: resultPrev.request.library.id)

        let a = urlSession(server: resultPrev.request.library.server).dataTaskPublisher(for: urlRequest)
            .tryMap { output in
                // print("\(#function) \(output.response.debugDescription) \(output.data.debugDescription)")
                guard let response = output.response as? HTTPURLResponse, response.statusCode == 200 else {
                    print("\(#function) error \(resultPrev.request.library.id)")
                    throw NSError(domain: "HTTP", code: 0, userInfo: nil)
                }
                
                return output.data
            }
            .decode(type: [String: CalibreCdbCmdListResult].self, decoder: JSONDecoder())
            .replaceError(with: ["result": CalibreCdbCmdListResult(book_ids: [-1])])
            .map { listResult -> CalibreSyncLibraryResult in
                var result = resultPrev
                if let list = listResult["result"] {
                    result.list = list
                }
                modelData.logFinishCalibreActivity(type: "Sync Library Books", request: urlRequest, startDatetime: startDatetime, finishDatetime: Date(), errMsg: result.list.book_ids.first == -1 ? "Failure" : "Success")
                return result
            }
            .eraseToAnyPublisher()
        
        return a
    }
    
    func getMetadata(oldbook: CalibreBook, completion: ((_ newbook: CalibreBook) -> Void)? = nil) {
        guard oldbook.library.server.isLocal == false else {
            modelData.updatingMetadataStatus = "Local File"
            modelData.updatingMetadataSucceed = true
            return
        }
        
        guard let serverUrl = getServerUrlByReachability(server: oldbook.library.server) else {
            modelData.updatingMetadataStatus = "Server not Reachable"
            return
        }
        
        var urlComponents = URLComponents()
        urlComponents.path = "/get/json/\(oldbook.id)/\(oldbook.library.key)"
        guard let endpointUrl = urlComponents.url(relativeTo: serverUrl) else {
            modelData.updatingMetadataStatus = "Internal Error"
            return
        }
        
        //let endpointUrl = URL(string: oldbook.library.server.serverUrl + "/get/json/\(oldbook.id)/" + oldbook.library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!

        let request = URLRequest(url: endpointUrl, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        let startDatetime = Date()
        modelData.logStartCalibreActivity(type: "Get Book Metadata", request: request, startDatetime: startDatetime, bookId: oldbook.id, libraryId: oldbook.library.id)

        let task = urlSession(server: oldbook.library.server).dataTask(with: request) { [self] data, response, error in
            var updatingMetadataStatus = "Unknonwn Error"
            var bookResult = oldbook
            defer {
                modelData.logFinishCalibreActivity(type: "Get Book Metadata", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: updatingMetadataStatus)
                
                DispatchQueue.main.async {
                    modelData.updatingMetadataStatus = updatingMetadataStatus
                    modelData.updatingMetadata = false
                    
                    if updatingMetadataStatus == "Success",
                       modelData.getBookRealm(forPrimaryKey: bookResult.inShelfId) != nil {
                        modelData.updateBook(book: bookResult)
                    }
                    
                    completion?(bookResult)
                }
            }
            if let error = error {
                defaultLog.warning("error: \(error.localizedDescription)")
                updatingMetadataStatus = error.localizedDescription
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                defaultLog.warning("not httpResponse: \(response.debugDescription)")
                updatingMetadataStatus = response.debugDescription
                return
            }
            guard httpResponse.statusCode != 404 else {
                defaultLog.warning("statusCode 404: \(httpResponse.debugDescription)")
                updatingMetadataStatus = "Deleted"
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                defaultLog.warning("statusCode not 2xx: \(httpResponse.debugDescription)")
                if let data = data,
                   let msg = String(data: data, encoding: .utf8) {
                    updatingMetadataStatus = msg
                } else {
                    updatingMetadataStatus = httpResponse.debugDescription
                }
                return
            }
            
            guard let mimeType = httpResponse.mimeType, mimeType == "application/json",
                  let data = data,
                  let string = String(data: data, encoding: .utf8) else {
                updatingMetadataStatus = httpResponse.debugDescription
                return
            }
            
                
            guard let newbook = handleLibraryBookOne(oldbook: oldbook, json: data) else {
                updatingMetadataStatus = "Failed to Parse Calibre Server Response."
                return
            }
            
//            if( newbook.readPos.getDevices().isEmpty) {
//                let pair = modelData.defaultReaderForDefaultFormat(book: newbook)
//                newbook.readPos.addInitialPosition(
//                    modelData.deviceName,
//                    pair.1.rawValue
//                )
//            }
                
            updatingMetadataStatus = "Success"
                
            bookResult = newbook
        }
        
        modelData.updatingMetadata = true
        
        task.resume()
    }
    
    func handleLibraryBookOne(oldbook: CalibreBook, json: Data) -> CalibreBook? {
        let decoder = JSONDecoder()
        
        do {
            let entry = try decoder.decode(CalibreBookEntry.self, from: json)
            guard let root = try JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
                return nil
            }
            
            var book = oldbook
            book.title = entry.title
            book.publisher = entry.publisher ?? ""
            book.series = entry.series ?? ""
            book.seriesIndex = entry.series_index ?? 0.0
            
            let parserOne = ISO8601DateFormatter()
            parserOne.formatOptions = .withInternetDateTime
            let parserTwo = ISO8601DateFormatter()
            parserTwo.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            book.pubDate = parserTwo.date(from: entry.pubdate) ?? parserOne.date(from: entry.pubdate) ?? .distantPast
            book.timestamp = parserTwo.date(from: entry.timestamp) ?? parserOne.date(from: entry.timestamp) ?? .init()
            book.lastModified = parserTwo.date(from: entry.last_modified) ?? parserOne.date(from: entry.last_modified) ?? .init()
            book.lastSynced = book.lastModified
            
            book.tags = entry.tags
            
            book.formats = entry.format_metadata.reduce(into: book.formats) {
                var formatInfo = $0[$1.key.uppercased()] ?? FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)
                
                formatInfo.serverSize = $1.value.size
                
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
                formatInfo.serverMTime = dateFormatter.date(from: $1.value.mtime) ?? .distantPast
                
                $0[$1.key.uppercased()] = formatInfo
            }
            
            book.size = 0   //parse later
            
            book.rating = Int(entry.rating * 2)
            book.authors = entry.authors
            book.identifiers = entry.identifiers
            book.comments = entry.comments ?? ""
            
            if let userMetadata = root["user_metadata"] as? NSDictionary {
                book.userMetadatas = userMetadata.reduce(into: book.userMetadatas) {
                    guard let dict = $1.value as? NSDictionary,
                        let label = dict["label"] as? String,
                        let value = dict["#value#"]
                    else { return }
                    $0[label] = value
                }
            }
            
            //Parse Reading Position
            if let pluginReadingPosition = modelData.calibreLibraries[oldbook.library.id]?.pluginReadingPositionWithDefault, pluginReadingPosition.isEnabled(),
               let readPosString = book.userMetadatas[pluginReadingPosition.readingPositionCN.trimmingCharacters(in: CharacterSet(["#"]))] as? String,
               let readPosData = Data(base64Encoded: readPosString) {
                if let readPosDictNew = try? decoder.decode([String:[String:BookDeviceReadingPosition]].self, from: readPosData),
                   let deviceMapDict = readPosDictNew["deviceMap"] {
                    
                    deviceMapDict.forEach { key, value in
                        let deviceName = key// as! String
                        
                        if let oldPos = book.readPos.getPosition(deviceName) {
                            guard deviceName != modelData.deviceName else { return }    //trust local record
                            guard oldPos.epoch < value.epoch else { return }            //server record may be compromised
                        }
                        
                        var deviceReadingPosition = value
                        deviceReadingPosition.id = deviceName
                        
                        book.readPos.updatePosition(deviceReadingPosition)
                        
                        defaultLog.info("book.readPos.getDevices().count \(book.readPos.getDevices().count)")
                    }
                    
                } else if let readPosDictNew = try? decoder.decode([String:[String:BookDeviceReadingPositionLegacy]].self, from: readPosData),
                          let deviceMapDictNew = readPosDictNew["deviceMap"],
                          let readPosDict = try? JSONSerialization.jsonObject(with: readPosData, options: []) as? NSDictionary,
                          let deviceMapDict = readPosDict["deviceMap"] as? NSDictionary {
                    
                    deviceMapDictNew.forEach { key, value in
                        let deviceName = key// as! String
                        
                        if let oldPos = book.readPos.getPosition(deviceName) {
                            guard deviceName != modelData.deviceName else { return }    //trust local record
                            guard oldPos.epoch < value.epoch else { return }            //server record may be compromised
                        }
                        
                        var deviceReadingPosition = BookDeviceReadingPosition(id: value.id, readerName: value.readerName, maxPage: value.maxPage, lastReadPage: value.lastReadPage, lastReadChapter: value.lastReadChapter, lastChapterProgress: value.lastChapterProgress, lastProgress: value.lastProgress, furthestReadPage: value.furthestReadPage, furthestReadChapter: value.furthestReadChapter, lastPosition: value.lastPosition, cfi: value.cfi, epoch: value.epoch, structuralStyle: value.structuralStyle, structuralRootPageNumber: value.structuralRootPageNumber, positionTrackingStyle: value.positionTrackingStyle, lastReadBook: value.lastReadBook, lastBundleProgress: value.lastBundleProgress)
                        
                        deviceReadingPosition.id = deviceName
                        
                        if let deviceReadingPositionDict = deviceMapDict[deviceName] as? [String: Any] {
                            if let cfi = deviceReadingPositionDict["cfi"] as? String {
                                deviceReadingPosition.cfi = cfi
                            }
                            deviceReadingPosition.epoch = deviceReadingPositionDict["epoch"] as? Double ?? .zero

                            deviceReadingPosition.structuralStyle = deviceReadingPositionDict["structuralStyle"] as? Int ?? .zero
                            deviceReadingPosition.structuralRootPageNumber = deviceReadingPositionDict["structuralRootPageNumber"] as? Int ?? .zero
                            deviceReadingPosition.positionTrackingStyle = deviceReadingPositionDict["positionTrackingStyle"] as? Int ?? .zero
                            deviceReadingPosition.lastReadBook = deviceReadingPositionDict["lastReadBook"] as? String ?? .init()
                            deviceReadingPosition.lastBundleProgress = deviceReadingPositionDict["lastBundleProgress"] as? Double ?? .zero
                        }
                        
                        book.readPos.updatePosition(deviceReadingPosition)
                        
                        defaultLog.info("book.readPos.getDevices().count \(book.readPos.getDevices().count)")
                    }
                }
            }

            return book
        } catch {
            print("\(#function) error=\(error)")
            return nil
        }
    }
    
    func handleLibraryBookOne(library: CalibreLibrary, bookRealm: CalibreBookRealm, entry: CalibreBookEntry, root: NSDictionary) {
        let decoder = JSONDecoder()
//
//        guard let entry = try? decoder.decode(CalibreBookEntry.self, from: json),
//              let root = try? JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
//            print("\(#function) decode error \(String(describing: bookRealm.primaryKey))")
//            return
//        }
        
//        bookRealm.serverUrl = library.server.baseUrl
//        bookRealm.serverUsername = library.server.username
//        bookRealm.libraryName = library.name
        
        bookRealm.title = entry.title
        bookRealm.publisher = entry.publisher ?? ""
        bookRealm.series = entry.series ?? ""
        bookRealm.seriesIndex = entry.series_index ?? 0.0
        
        let parserOne = ISO8601DateFormatter()
        parserOne.formatOptions = .withInternetDateTime
        let parserTwo = ISO8601DateFormatter()
        parserTwo.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        bookRealm.pubDate = parserTwo.date(from: entry.pubdate) ?? parserOne.date(from: entry.pubdate) ?? .distantPast
        bookRealm.timestamp = parserTwo.date(from: entry.timestamp) ?? parserOne.date(from: entry.timestamp) ?? .distantPast
        bookRealm.lastModified = parserTwo.date(from: entry.last_modified) ?? parserOne.date(from: entry.last_modified) ?? .distantPast
        bookRealm.lastSynced = bookRealm.lastModified
        
        var authors = entry.authors
        bookRealm.authorFirst = authors.popFirst() ?? "Unknown"
        bookRealm.authorSecond = authors.popFirst()
        bookRealm.authorThird = authors.popFirst()
        bookRealm.authorsMore.replaceSubrange(bookRealm.authorsMore.indices, with: authors)
        
        var tags = entry.tags
        bookRealm.tagFirst = tags.popFirst()
        bookRealm.tagSecond = tags.popFirst()
        bookRealm.tagThird = tags.popFirst()
        bookRealm.tagsMore.replaceSubrange(bookRealm.tagsMore.indices, with: tags)
        
        var formats: [String : FormatInfo] = (try? decoder.decode([String:FormatInfo].self, from: bookRealm.formatsData as Data? ?? .init())) ?? [:]

        formats = entry.format_metadata.reduce(into: formats) {
            var formatInfo = $0[$1.key.uppercased()] ?? FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)
            
            formatInfo.serverSize = $1.value.size
            
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
            formatInfo.serverMTime = dateFormatter.date(from: $1.value.mtime) ?? .distantPast
            
            $0[$1.key.uppercased()] = formatInfo
        }
        bookRealm.formatsData = try? JSONEncoder().encode(formats) as NSData?
        
        bookRealm.size = 0   //parse later
        
        bookRealm.rating = Int(entry.rating * 2)
        
        bookRealm.identifiersData = try? JSONEncoder().encode(entry.identifiers) as NSData
        bookRealm.comments = entry.comments ?? ""
        
        var userMetadatas = bookRealm.userMetadatas()
        if let userMetadata = root["user_metadata"] as? NSDictionary {
            userMetadatas = userMetadata.reduce(into: userMetadatas) {
                guard let dict = $1.value as? NSDictionary,
                    let label = dict["label"] as? String,
                    let value = dict["#value#"]
                else { return }
                $0[label] = value
            }
        }
        bookRealm.userMetaData = try? JSONSerialization.data(withJSONObject: userMetadatas, options: []) as NSData
        var readPos = bookRealm.readPos(library: library)
        //Parse Reading Position
        if let pluginReadingPosition = modelData.calibreLibraries[library.id]?.pluginReadingPositionWithDefault, pluginReadingPosition.isEnabled(),
           let readPosString = userMetadatas[pluginReadingPosition.readingPositionCN.trimmingCharacters(in: CharacterSet(["#"]))] as? String,
           let readPosData = Data(base64Encoded: readPosString) {
            
            if let readPosDictNew = try? decoder.decode([String:[String:BookDeviceReadingPosition]].self, from: readPosData),
               let deviceMapDict = readPosDictNew["deviceMap"] {
                
                deviceMapDict.forEach { key, value in
                    let deviceName = key// as! String
                    
                    if let oldPos = readPos.getPosition(deviceName) {
                        guard deviceName != modelData.deviceName else { return }    //trust local record
                        guard oldPos.epoch < value.epoch else { return }            //server record may be compromised
                    }
                    
                    var deviceReadingPosition = value
                    deviceReadingPosition.id = deviceName
                    
                    readPos.updatePosition(deviceReadingPosition)
                }
                
                
            } else if let readPosDictNew = try? decoder.decode([String:[String:BookDeviceReadingPositionLegacy]].self, from: readPosData),
                      let deviceMapDictNew = readPosDictNew["deviceMap"],
                      let readPosDict = try? JSONSerialization.jsonObject(with: readPosData, options: []) as? NSDictionary,
                      let deviceMapDict = readPosDict["deviceMap"] as? NSDictionary {
                
                deviceMapDictNew.forEach { key, value in
                    let deviceName = key// as! String
                    
                    if let oldPos = readPos.getPosition(deviceName) {
                        guard deviceName != modelData.deviceName else { return }    //trust local record
                        guard oldPos.epoch < value.epoch else { return }            //server record may be compromised
                    }
                    
                    var deviceReadingPosition = BookDeviceReadingPosition(id: value.id, readerName: value.readerName, maxPage: value.maxPage, lastReadPage: value.lastReadPage, lastReadChapter: value.lastReadChapter, lastChapterProgress: value.lastChapterProgress, lastProgress: value.lastProgress, furthestReadPage: value.furthestReadPage, furthestReadChapter: value.furthestReadChapter, lastPosition: value.lastPosition, cfi: value.cfi, epoch: value.epoch, structuralStyle: value.structuralStyle, structuralRootPageNumber: value.structuralRootPageNumber, positionTrackingStyle: value.positionTrackingStyle, lastReadBook: value.lastReadBook, lastBundleProgress: value.lastBundleProgress)
                    
                    deviceReadingPosition.id = deviceName
                    
                    if let deviceReadingPositionDict = deviceMapDict[deviceName] as? [String: Any] {
                        if let cfi = deviceReadingPositionDict["cfi"] as? String {
                            deviceReadingPosition.cfi = cfi
                        }
                        deviceReadingPosition.epoch = deviceReadingPositionDict["epoch"] as? Double ?? .zero
                        
                        deviceReadingPosition.structuralStyle = deviceReadingPositionDict["structuralStyle"] as? Int ?? .zero
                        deviceReadingPosition.structuralRootPageNumber = deviceReadingPositionDict["structuralRootPageNumber"] as? Int ?? .zero
                        deviceReadingPosition.positionTrackingStyle = deviceReadingPositionDict["positionTrackingStyle"] as? Int ?? .zero
                        deviceReadingPosition.lastReadBook = deviceReadingPositionDict["lastReadBook"] as? String ?? .init()
                        deviceReadingPosition.lastBundleProgress = deviceReadingPositionDict["lastBundleProgress"] as? Double ?? .zero
                    }
                    
                    readPos.updatePosition(deviceReadingPosition)
                }
            }
            
        }
        
        let encoder = JSONEncoder()
        let deviceMapSerialize = readPos.getCopy().compactMapValues { (value) -> Any? in
            try? JSONSerialization.jsonObject(with: encoder.encode(value))
        }
        bookRealm.readPosData = try? JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []) as NSData
        
        bookRealm.lastProgress = readPos.getDevices().max(by: { lbdrp, rbdrp in
            lbdrp.lastProgress < rbdrp.lastProgress
        })?.lastProgress ?? 0.0
    }
    
    func getBookManifest(book: CalibreBook, format: Format, completion: ((_ manifest: Data?) -> Void)? = nil) {
        let endpointUrl = URL(string: book.library.server.serverUrl + "/book-manifest/\(book.id)/\(format.id)?library_id=" + book.library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!

        let request = URLRequest(url: endpointUrl)
        
        let startDatetime = Date()
        modelData.logStartCalibreActivity(type: "Get Book Manifest", request: request, startDatetime: startDatetime, bookId: book.id, libraryId: book.library.id)

        let task = urlSession(server: book.library.server).dataTask(with: request) { [self] data, response, error in
            var updatingMetadataStatus = "Unknown Error"
            defer {
                modelData.logFinishCalibreActivity(type: "Get Book Manifest", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: updatingMetadataStatus)
                DispatchQueue.main.async {
                    modelData.updatingMetadataStatus = updatingMetadataStatus
                    modelData.updatingMetadata = false
                    completion?(data)
                }
            }
            if let error = error {
                defaultLog.warning("error: \(error.localizedDescription)")
                updatingMetadataStatus = error.localizedDescription
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                defaultLog.warning("not httpResponse: \(response.debugDescription)")
                updatingMetadataStatus = response.debugDescription
                return
            }
            
            guard httpResponse.statusCode != 404 else {
                updatingMetadataStatus = "Deleted"
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                defaultLog.warning("statusCode not 2xx: \(httpResponse.debugDescription)")
                updatingMetadataStatus = httpResponse.debugDescription
                return
            }
            
            if let mimeType = httpResponse.mimeType, mimeType == "application/json",
               let data = data {
                updatingMetadataStatus = "Success"
            }
        }
        
        modelData.updatingMetadata = true

        task.resume()
    }
    
    ///metadata: [[key1, value1], [key2, value2], ...]
    func updateMetadata(library: CalibreLibrary, bookId: Int32, metadata: [Any]) -> Int {
        guard var endpointURLComponent = URLComponents(string: library.server.serverUrl) else {
            return -1
        }
        
        endpointURLComponent.path.append("/cdb/cmd/set_metadata/0")
        endpointURLComponent.queryItems = [
            URLQueryItem(name: "library_id", value: library.key)
        ]
        guard let endpointUrl = endpointURLComponent.url else {
            return -1
        }
        
        let json:[Any] = ["fields", bookId, metadata]
        
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else {
            return -1
        }
        defaultLog.warning("JSON: \(String(data: data, encoding: .utf8)!)")
        
        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "POST"
        request.httpBody = data
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
//        if updatingMetadata && updatingMetadataTask != nil {
//            updatingMetadataTask!.cancel()
//        }
        let startDatetime = Date()
        modelData.logStartCalibreActivity(type: "Set Book Metadata", request: request, startDatetime: startDatetime, bookId: bookId, libraryId: library.id)

        let updatingMetadataTask = urlSession(server: library.server).dataTask(with: request) { [self] data, response, error in
            print("\(#function) \(data) \(response) \(error)")
            modelData.logFinishCalibreActivity(type: "Set Book Metadata", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: "Finished")
        }
        
        updatingMetadataTask.resume()
        
        return 0
    }
    
    @available(*, deprecated, message: "replaced by book-set-last-read-position")
    func updateBookReadingPosition(book: CalibreBook, columnName: String, alertDelegate: AlertDelegate?, success: (() -> Void)?) -> Int {
        guard var endpointURLComponent = URLComponents(string: book.library.server.serverUrl) else {
            return -1
        }
        
        endpointURLComponent.path.append("/cdb/cmd/set_metadata/0")
        endpointURLComponent.queryItems = [
            URLQueryItem(name: "library_id", value: book.library.key)
        ]
        guard let endpointUrl = endpointURLComponent.url else {
            return -1
        }
        
        var deviceMapSerialize = [String: Any]()
        
        book.readPos.getCopy().forEach { key, value in
            guard let jsonObject = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) else {
                return
            }
            deviceMapSerialize[key] = jsonObject
        }
        
        guard deviceMapSerialize.count == book.readPos.getCopy().count else {
            return -1
        }
        
        guard let readPosData = try? JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []).base64EncodedString() else { return -1 }
        
        let json:[Any] = ["fields", book.id, [[columnName, readPosData]]]
        
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else {
            return -1
        }
        defaultLog.warning("JSON: \(String(data: data, encoding: .utf8)!)")
        
        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "POST"
        request.httpBody = data
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let startDatetime = Date()
        modelData.logStartCalibreActivity(type: "Update Reading Position", request: request, startDatetime: startDatetime, bookId: book.id, libraryId: book.library.id)
        
        let updatingMetadataTask = urlSession(server: book.library.server).dataTask(with: request) { [self] data, response, error in
            var updatingMetadataStatus = "Unknown Error"
            var newBook = book
            
            defer {
                modelData.logFinishCalibreActivity(type: "Update Reading Position", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: updatingMetadataStatus)

                DispatchQueue.main.async {
                    modelData.updatingMetadataStatus = updatingMetadataStatus
                    modelData.updatingMetadata = false
                    
                    if updatingMetadataStatus == "Success" {
                        modelData.updateBook(book: newBook)
                        success?()
                    } else {
                        alertDelegate?.alert(msg: updatingMetadataStatus)
                    }
                }
            }
            if let error = error {
                defaultLog.warning("error: \(error.localizedDescription)")
                updatingMetadataStatus = error.localizedDescription
                return
            }
            var dataAsString = ""
            if let data = data, let s = String(data: data, encoding: .utf8) {
                dataAsString = s
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                defaultLog.warning("not httpResponse: \(response.debugDescription)")
                updatingMetadataStatus = dataAsString + response.debugDescription
                return
            }
            if !(200...299).contains(httpResponse.statusCode) {
                defaultLog.warning("statusCode not 2xx: \(httpResponse.debugDescription)")
                updatingMetadataStatus =
                    httpResponse.statusCode.description
                    + " " + HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                    + " " + dataAsString
                    + " " + httpResponse.debugDescription
                return
            }
            
            guard let mimeType = httpResponse.mimeType, mimeType == "application/json",
                  let data = data else {
                updatingMetadataStatus = dataAsString + httpResponse.debugDescription
                return
            }
            
            guard let root = try? JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary else {
                updatingMetadataStatus = dataAsString + httpResponse.debugDescription
                return
            }
            
            guard let result = root["result"] as? NSDictionary, let resultv = result["v"] as? NSDictionary else {
                updatingMetadataStatus = dataAsString + httpResponse.debugDescription
                return
            }

            print("updateCurrentPosition result=\(result)")
            
            guard let lastModifiedDict = resultv["last_modified"] as? NSDictionary,
                  var lastModifiedV = lastModifiedDict["v"] as? String
            else {
                updatingMetadataStatus = "Unrecognized server reponse"
                return
            }
            
            print("last_modified \(lastModifiedV)")
            if let idxMilli = lastModifiedV.firstIndex(of: "."), let idxTZ = lastModifiedV.firstIndex(of: "+"), idxMilli < idxTZ {
                lastModifiedV = lastModifiedV.replacingCharacters(in: idxMilli..<idxTZ, with: "")
            }
            print("last_modified_new \(lastModifiedV)")
            
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = .withInternetDateTime
            guard let date = dateFormatter.date(from: lastModifiedV) else {
                updatingMetadataStatus = "Unrecognized server reponse"
                return
            }
            
            newBook.lastModified = date
            updatingMetadataStatus = "Success"
        }
        
        modelData.updatingMetadata = true
        
        updatingMetadataTask.resume()
        
        return 0
    }
    
    func getProtectionSpace(server: CalibreServer, port: Int?) -> URLProtectionSpace? {
        guard server.username.count > 0 && server.password.count > 0,
              let url = getServerUrlByReachability(server: server),
              let host = url.host
        else { return nil }
        
        var authMethod = NSURLAuthenticationMethodDefault
        if url.scheme == "http" {
            authMethod = NSURLAuthenticationMethodHTTPDigest
        }
        if url.scheme == "https" {
            authMethod = NSURLAuthenticationMethodHTTPBasic
        }
        return URLProtectionSpace.init(host: host,
                                       port: port ?? url.port ?? 0,
                                       protocol: url.scheme,
                                       realm: "calibre",
                                       authenticationMethod: authMethod)
    }
    
    func getServerUrlByReachability(server: CalibreServer) -> URL? {
        let serverInfos = modelData.calibreServerInfoStaging.filter { $1.reachable && $1.server.id == server.id }.sorted { !$0.value.isPublic && $1.value.isPublic }
        guard let serverInfo = serverInfos.first else { return nil }
        
        if serverInfo.value.isPublic {
            return URL(string: server.publicUrl)
        } else {
            return URL(string: server.baseUrl)
        }
    }
    
    // MARK: - Combine style below
    
    func probeServerReachabilityNew(serverInfo: CalibreServerInfo) -> AnyPublisher<CalibreServerInfo, Never> {
        var serverInfo = serverInfo
        
        serverInfo.reachable = false
        serverInfo.errorMsg = "Cannot connect"
        
        var url = serverInfo.url
        url.appendPathComponent("/ajax/library-info", isDirectory: false)
        
        return urlSession(server: serverInfo.server, timeout: 10).dataTaskPublisher(for: url)
            .map { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    serverInfo.errorMsg = "Cannot get HTTP response"
                    return serverInfo
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    serverInfo.errorMsg = httpResponse.description
                    return serverInfo
                }
                guard let libraryInfo = try? JSONDecoder().decode(CalibreServerLibraryInfo.self, from: data) else {
                    serverInfo.errorMsg = "Cannot parse library list"
                    return serverInfo
                }
                guard let defaultLibrary = libraryInfo.defaultLibrary,
                      libraryInfo.libraryMap.count > 0 else {
                    serverInfo.errorMsg = "Server has no library"
                    return serverInfo
                }
          
                serverInfo.defaultLibrary = defaultLibrary
                serverInfo.libraryMap = libraryInfo.libraryMap
                serverInfo.errorMsg = "Success"
                serverInfo.reachable = true

                return serverInfo
            }
            .catch({ error in
                if error.errorCode == URLError.Code.cancelled.rawValue {
                    serverInfo.errorMsg = "cancelled, server may require authentication"
                } else {
                    serverInfo.errorMsg = error.localizedDescription
                }
                
                return Just(serverInfo).setFailureType(to: Never.self).eraseToAnyPublisher()
            })
            .eraseToAnyPublisher()
    }
    
    func buildProbeLibraryTask(library: CalibreLibrary) -> CalibreLibraryProbeTask? {
        guard let serverUrl =
                modelData.librarySyncStatus[library.id]?.isError == true
                ? URL(fileURLWithPath: "/realm")
                : (
                    getServerUrlByReachability(server: library.server) ?? (
                        (library.autoUpdate || library.server.isLocal)
                        ? URL(fileURLWithPath: "/realm")
                        : nil
                    )
                )
        else { return nil }
        
        var probeUrlComponents = URLComponents()
        probeUrlComponents.path = "ajax/search/\(library.key)"
        
        var probeUrlQueryItems = [URLQueryItem]()
        
        probeUrlQueryItems.append(.init(name: "num", value: "0"))
        
        probeUrlComponents.queryItems = probeUrlQueryItems
        
        guard let probeUrl = probeUrlComponents.url(relativeTo: serverUrl)?.absoluteURL else {
            return nil
        }
        
        return .init(
            library: library,
            probeUrl: probeUrl
        )
    }
    
    func buildMetadataTask(library: CalibreLibrary, bookId: Int32) -> CalibreBookTask? {
        guard let serverUrl = getServerUrlByReachability(server: library.server) else {
            return nil
        }
        var urlComponents = URLComponents()
        urlComponents.path = "/get/json/\(bookId)/\(library.key)"
        guard let endpointUrl = urlComponents.url(relativeTo: serverUrl)?.absoluteURL else {
            return nil
        }
        
        return CalibreBookTask(
            server: library.server,
            bookId: bookId,
            inShelfId: "",
            url: endpointUrl)
    }
    
    func buildMetadataTask(book: CalibreBook) -> CalibreBookTask? {
        guard let serverUrl = getServerUrlByReachability(server: book.library.server) else {
            return nil
        }
        var urlComponents = URLComponents()
        urlComponents.path = "/get/json/\(book.id)/\(book.library.key)"
        guard let endpointUrl = urlComponents.url(relativeTo: serverUrl)?.absoluteURL else {
            return nil
        }
        
        return CalibreBookTask(
            server: book.library.server,
            bookId: book.id,
            inShelfId: book.inShelfId,
            url: endpointUrl)
    }
    
    func buildBooksMetadataTask(library: CalibreLibrary, books: [CalibreBook], getAnnotations: Bool = false, searchTask: CalibreLibrarySearchTask? = nil) -> CalibreBooksTask? {
        let serverUrl = getServerUrlByReachability(server: library.server) ?? URL(fileURLWithPath: "/realm")
        
        let bookIds = books.map{ $0.id.description }
        
        var urlComponents = URLComponents()
        urlComponents.path = "/ajax/books/\(library.key)"
        urlComponents.queryItems = [
            URLQueryItem(name: "ids", value: bookIds.joined(separator: ","))
        ]
        guard let endpointUrl = urlComponents.url(relativeTo: serverUrl)?.absoluteURL else {
            return nil
        }
        
        let which = books.map {
            let id = $0.id.description
            return $0.formats.filter { $0.value.cached }.map { "\(id)-\($0.key)" }.joined(separator: "_")
        }.joined(separator: "_")
        
        var lastReadPositionUrlComponents = URLComponents()
        lastReadPositionUrlComponents.path = "/book-get-last-read-position/\(library.key)/\(which)"
        guard let lastReadPositionEndpointUrl = lastReadPositionUrlComponents.url(relativeTo: serverUrl)?.absoluteURL else {
            return nil
        }
        
        var annotationsUrlComponents = URLComponents()
        annotationsUrlComponents.path = "/book-get-annotations/\(library.key)/\(which)"
        guard let annotationsEndpointUrl = annotationsUrlComponents.url(relativeTo: serverUrl)?.absoluteURL else {
            return nil
        }
        
        print("\(#function) endpointUrl=\(endpointUrl.absoluteString)")
        
        return CalibreBooksTask(
            request: .init(library: library, books: books.map{ $0.id }, getAnnotations: getAnnotations),
            metadataUrl: endpointUrl,
            lastReadPositionUrl: lastReadPositionEndpointUrl,
            annotationsUrl: annotationsEndpointUrl,
            searchTask: searchTask
        )
    }
    
    func getMetadata(task: CalibreBookTask) -> AnyPublisher<(CalibreBookTask, CalibreBookEntry), Never> {
        return urlSession(server: task.server).dataTaskPublisher(for: task.url)
            .map { $0.data }
            .decode(type: CalibreBookEntry.self, decoder: JSONDecoder())
            .replaceError(with: CalibreBookEntry())
            .map { (task, $0) }
            .eraseToAnyPublisher()
    }
    
    func getMetadataNew(task: CalibreBookTask) -> AnyPublisher<(CalibreBookTask, Data, URLResponse), URLError> {
        return urlSession(server: task.server)
            .dataTaskPublisher(for: task.url)
            .map { (task, $0.data, $0.response) }
            .eraseToAnyPublisher()
    }
    
    func getBooksMetadata(task: CalibreBooksTask, qos: DispatchQoS.QoSClass = .default) -> AnyPublisher<CalibreBooksTask, URLError> {
        guard let metadataUrl = task.metadataUrl,
              metadataUrl.isHTTP else {
            return Just(task).setFailureType(to: URLError.self).eraseToAnyPublisher()
        }
        guard task.books.isEmpty == false else {
            return Just(task).setFailureType(to: URLError.self).eraseToAnyPublisher()
        }
        
        return urlSession(server: task.library.server, qos: qos)
            .dataTaskPublisher(for: metadataUrl)
            .map { result -> CalibreBooksTask in
                var task = task
                task.data = result.data
                task.response = result.response
                do {
                    task.booksMetadataEntry = try JSONDecoder().decode([String:CalibreBookEntry?].self, from: result.data)
                    task.booksMetadataJSON = try JSONSerialization.jsonObject(with: result.data, options: []) as? NSDictionary
                } catch let DecodingError.keyNotFound(key, context) {
                    print("getBookMetadataCancellable decode keyNotFound \(task.library.name) \(key) \(context) \(task.data?.count ?? -1)")
                    if let firstCodingPath = context.codingPath.first,
                       let bookId = Int32(firstCodingPath.stringValue),
                       bookId > 0 {
                        task.booksError.insert(bookId)
                    } else if task.books.count == 1 {
                        task.booksError.formUnion(task.books)
                    }
                } catch {
                    print("getBookMetadataCancellable decode \(task.library.name) \(error) \(task.data?.count ?? -1)")
                    if task.books.count == 1 {
                        task.booksError.formUnion(task.books)
                    }
                }
                return task
            }
            .eraseToAnyPublisher()
    }
    
    func getLastReadPosition(task: CalibreBooksTask) -> AnyPublisher<CalibreBooksTask, URLError> {
        guard let lastReadPositionUrl = task.lastReadPositionUrl,
              lastReadPositionUrl.isHTTP
        else {
            return Just(task)
                .setFailureType(to: URLError.self)
                .eraseToAnyPublisher()
        }
        return urlSession(server: task.library.server).dataTaskPublisher(for: lastReadPositionUrl)
            .map { result -> CalibreBooksTask in
                var task = task
                task.lastReadPositionsData = result.data
                return task
            }
            .eraseToAnyPublisher()
    }
    
    func getAnnotations(task: CalibreBooksTask) -> AnyPublisher<CalibreBooksTask, URLError> {
        guard let annotationsUrl = task.annotationsUrl,
              annotationsUrl.isHTTP
        else {
            return Just(task)
                .setFailureType(to: URLError.self)
                .eraseToAnyPublisher()
        }
        return urlSession(server: task.library.server).dataTaskPublisher(for: annotationsUrl)
            .map { result -> CalibreBooksTask in
                var task = task
                task.annotationsData = result.data
                do {
                    task.booksAnnotationsEntry = try JSONDecoder().decode([String:CalibreBookAnnotationsResult].self, from: result.data)
                } catch {
                    print("\(#function) annotationEntry error=\(error)")
                }
                return task
            }
            .eraseToAnyPublisher()
    }
    
    func buildSetLastReadPositionTask(library: CalibreLibrary, bookId: Int32, format: Format, entry: CalibreBookLastReadPositionEntry) -> CalibreBookSetLastReadPositionTask? {
        guard let serverUrl = getServerUrlByReachability(server: library.server) else {
            return nil
        }
        
        var lastReadPositionUrlComponents = URLComponents()
        lastReadPositionUrlComponents.path = "/book-set-last-read-position/\(library.key)/\(bookId)/\(format.rawValue)"
        guard let lastReadPositionEndpointUrl = lastReadPositionUrlComponents.url(relativeTo: serverUrl)?.absoluteURL else {
            return nil
        }
        
        guard let postData = try? JSONEncoder().encode(entry) else {
            return nil
        }
        
        var urlRequest = URLRequest(url: lastReadPositionEndpointUrl)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = postData
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")
        
        return CalibreBookSetLastReadPositionTask(
            library: library,
            bookId: bookId,
            format: format,
            entry: entry,
            urlRequest: urlRequest
        )
    }
    
    func setLastReadPositionByTask(task: CalibreBookSetLastReadPositionTask) -> AnyPublisher<CalibreBookSetLastReadPositionTask, Never> {
        urlSession(server: task.library.server).dataTaskPublisher(for: task.urlRequest)
            .map { result -> CalibreBookSetLastReadPositionTask in
                var task = task
                task.urlResponse = result.response
                task.data = result.data
                return task
            }
            .replaceError(with: task)
            .eraseToAnyPublisher()
    }
    
    func buildUpdateAnnotationsTask(library: CalibreLibrary, bookId: Int32, format: Format, highlights: [CalibreBookAnnotationHighlightEntry], bookmarks: [CalibreBookAnnotationBookmarkEntry]) -> CalibreBookUpdateAnnotationsTask? {
        guard let serverUrl = getServerUrlByReachability(server: library.server) else {
            return nil
        }
        
        var endpointURLComponent = URLComponents()
        endpointURLComponent.path = "/book-update-annotations/\(library.key)/\(bookId)/\(format.rawValue)"
        guard let endpointUrl = endpointURLComponent.url(relativeTo: serverUrl)?.absoluteURL else {
            return nil
        }
        
        let encoder = JSONEncoder()
        var annotations = [Any]()
        annotations.append(contentsOf: highlights.compactMap {
            guard let data = try? encoder.encode($0) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        })
        annotations.append(contentsOf: bookmarks.compactMap {
            guard let data = try? encoder.encode($0) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        })
        
        let entry = ["\(bookId):\(format.rawValue)":annotations]
        guard let postData = try? JSONSerialization.data(withJSONObject: entry) else {
            return nil
        }
        
        var urlRequest = URLRequest(url: endpointUrl)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = postData
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")
        
        return CalibreBookUpdateAnnotationsTask(
            library: library,
            bookId: bookId,
            format: format,
            entry: entry,
            urlRequest: urlRequest
        )
    }
    
    func updateAnnotationByTask(task: CalibreBookUpdateAnnotationsTask) -> AnyPublisher<CalibreBookUpdateAnnotationsTask, Never> {
        urlSession(server: task.library.server).dataTaskPublisher(for: task.urlRequest)
            .map { result -> CalibreBookUpdateAnnotationsTask in
                var task = task
                task.urlResponse = result.response
                task.data = result.data
                return task
            }
            .replaceError(with: task)
            .eraseToAnyPublisher()
    }
    
    func getCustomColumnsPublisher(request: CalibreSyncLibraryRequest) -> AnyPublisher<CalibreSyncLibraryResult, Never> {
        let error: [String: [String:CalibreCustomColumnInfo]] = ["error":[:]]

        guard let serverURL = getServerUrlByReachability(server: request.library.server),
              var endpointURLComponent = URLComponents(string: serverURL.absoluteString) else {
            return Just(
                CalibreSyncLibraryResult(
                    request: request,
                    result: error
                )
            ).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        endpointURLComponent.path.append("/cdb/cmd/custom_columns/0")
        endpointURLComponent.queryItems = [URLQueryItem(name: "library_id", value: request.library.key)]

        guard let endpointUrl = endpointURLComponent.url else {
            return Just(
                CalibreSyncLibraryResult(
                    request: request,
                    result: error
                )
            ).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        guard let postData = "[]".data(using: .utf8) else {
            return Just(
                CalibreSyncLibraryResult(
                    request: request,
                    result: error
                )
            ).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: endpointUrl)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = postData
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")

        let a = urlSession(server: request.library.server)
            .dataTaskPublisher(for: urlRequest)
            .map { output -> CalibreSyncLibraryResult in
                if let result = try? JSONDecoder().decode([String: [String:CalibreCustomColumnInfo]].self, from: output.data) {
                    return CalibreSyncLibraryResult(
                        request: request,
                        result: result
                    )
                } else {
                    var libraryResult = CalibreSyncLibraryResult(
                        request: request,
                        result: error
                    )
                    if let httpResponse = output.response as? HTTPURLResponse {
                        if (400...499).contains(httpResponse.statusCode) {
                            libraryResult.errmsg = String(data: output.data, encoding: .utf8) ?? "Code \(httpResponse.statusCode)"
                        }
                    }
                    return libraryResult
                }
            }
            .replaceError(with: .init(
                request: request,
                result: error)
            ).eraseToAnyPublisher()
        
        return a
    }
    
    func getLibraryCategoriesPublisher(resultPrev: CalibreSyncLibraryResult) -> AnyPublisher<CalibreSyncLibraryResult, Never> {
        var urlComponents = URLComponents()
        urlComponents.path = "ajax/categories/\(resultPrev.request.library.key)"
        
        guard let serverUrl = getServerUrlByReachability(server: resultPrev.request.library.server),
              let endpointUrl = urlComponents.url(relativeTo: serverUrl)
        else {
            var result = resultPrev
            result.errmsg = "Server not Reachable"
            return Just(result).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        return urlSession(server: resultPrev.request.library.server).dataTaskPublisher(for: endpointUrl)
            .map {
                $0.data
            }
            .decode(type: [CalibreLibraryCategory].self, decoder: JSONDecoder())
            .replaceError(with: [])
            .map { categories -> CalibreSyncLibraryResult in
                var result = resultPrev
                result.categories = categories
                return result
            }
            .eraseToAnyPublisher()
    }
}

struct CalibreServerURLSessionKey: Hashable, Equatable {
    let server: CalibreServer
    let timeout: Double
    let qos: DispatchQoS.QoSClass
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(server.uuid)
        hasher.combine(timeout)
        hasher.combine(qos)
    }
}

struct CalibreServerLibraryInfo: Codable {
    var defaultLibrary: String?
    var libraryMap: [String:String]
    
    enum CodingKeys: String, CodingKey {
        case defaultLibrary = "default_library"
        case libraryMap = "library_map"
    }
}

struct CalibreServerInfo: Identifiable {
    var id: String {
        server.id + " " + isPublic.description
    }
    
    let server: CalibreServer
    let isPublic: Bool
    let url: URL
    var reachable: Bool = false
    var probing: Bool = false
    var errorMsg: String = "Waiting to connect"
    var defaultLibrary: String
    var libraryMap: [String:String] = [:]
    
    var request: CalibreProbeServerRequest
}

struct CalibreLibraryInfo: Identifiable {
    var id: String {
        library.id
    }
    
    let library: CalibreLibrary
    
    let totalNumber: Int
    let errorMessage: String
}

class CalibreServerTaskDelegate: NSObject, URLSessionTaskDelegate {
//    let username: String
    
    var userCredential: URLCredential?
    
    init(_ server: CalibreServer) {
//        if server.username.count > 0,
//           server.password.count > 0,
//           let host = url.host {
//            var authMethod = NSURLAuthenticationMethodDefault
//            if url.scheme == "http" {
//                authMethod = NSURLAuthenticationMethodHTTPDigest
//            }
//            if url.scheme == "https" {
//                authMethod = NSURLAuthenticationMethodHTTPBasic
//            }
//            let protectionSpace = URLProtectionSpace.init(host: host,
//                                                          port: url.port ?? 0,
//                                                          protocol: url.scheme,
//                                                          realm: "calibre",
//                                                          authenticationMethod: authMethod)
//
//        }
        if server.username.isEmpty == false,
           server.password.isEmpty == false {
            userCredential = URLCredential(user: server.username,
                                           password: server.password,
                                           persistence: .forSession)
        }
    }
    
    func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                  didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let userCredential = userCredential,
              challenge.previousFailureCount < 3 else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        print("CalibreServerTaskDelegate \(task) \(challenge.previousFailureCount) \(challenge.protectionSpace)")
        
//        let credentials = URLCredentialStorage.shared.credentials(for: challenge.protectionSpace)
        completionHandler(.useCredential, userCredential)
    }
}

func uuidFolioToCalibre(_ identifier: String) -> String? {
    guard let tempUuid = NSUUID(uuidString: identifier) else {
        return nil
    }
    var tempUuidBytes: UInt8 = 0
    tempUuid.getBytes(&tempUuidBytes)
    let data = Data(bytes: &tempUuidBytes, count: 16)
    let base64 = data.base64EncodedString(options: NSData.Base64EncodingOptions())
    return base64ToBase64URL(base64: base64)
}

func uuidCalibreToFolio(_ shortenedIdentifier: String?) -> String? {
    // Expand an identifier out of a CBAdvertisementDataLocalNameKey or service characteristic.
    guard let shortenedIdentifier = shortenedIdentifier else {
        return nil
    }
    // Rehydrate the shortenedIdentifier
    let shortenedIdentifierWithDoubleEquals = base64urlToBase64(base64url: shortenedIdentifier)
    guard let data = Data(base64Encoded: shortenedIdentifierWithDoubleEquals),
          let uuidBytes = data.withUnsafeBytes({ $0.baseAddress?.assumingMemoryBound(to: UInt8.self) })
    else { return nil }
    
    let tempUuid = NSUUID(uuidBytes: uuidBytes)
    
    return tempUuid.uuidString
}

func base64urlToBase64(base64url: String) -> String {
    var base64 = base64url
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let paddingNum = 4 - base64.count % 4
    if paddingNum != 4 {
        base64.append(String(repeating: "=", count: paddingNum))
    }
    return base64
}

func base64ToBase64URL(base64: String) -> String {
    let base64url = base64
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return base64url
}
