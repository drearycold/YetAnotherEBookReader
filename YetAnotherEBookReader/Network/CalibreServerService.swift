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

    func getServerLibraries(server: CalibreServer) {
        modelData.calibreServerInfo = nil
        modelData.calibreServerUpdatingStatus = "Initializing"

        var serverInfo = CalibreServerInfo(server: server, isPublic: server.usePublic, url: URL(fileURLWithPath: "/"), reachable: false, errorMsg: "Server URL Malformed", defaultLibrary: "", libraryMap: [:])

        guard let serverUrl = getServerUrlByReachability(server: server) ?? URL(string: server.baseUrl) else {
            modelData.calibreServerInfo = serverInfo
            modelData.calibreServerUpdatingStatus = serverInfo.errorMsg
            return
        }
        
        var urlComponents = URLComponents()
        urlComponents.path = "ajax/library-info"
        
        guard let url = urlComponents.url(relativeTo: serverUrl), let host = url.host else {
            modelData.calibreServerInfo = serverInfo
            modelData.calibreServerUpdatingStatus = serverInfo.errorMsg
            return
        }
        //url.appendPathComponent("/ajax/library-info", isDirectory: false)
        
        if server.username.count > 0 && server.password.count > 0 {
            var authMethod = NSURLAuthenticationMethodDefault
            if url.scheme == "http" {
                authMethod = NSURLAuthenticationMethodHTTPDigest
            }
            if url.scheme == "https" {
                authMethod = NSURLAuthenticationMethodHTTPBasic
            }
            let protectionSpace = URLProtectionSpace.init(host: host,
                                                          port: url.port ?? 0,
                                                          protocol: url.scheme,
                                                          realm: "calibre",
                                                          authenticationMethod: authMethod)
            let userCredential = URLCredential(user: server.username,
                                               password: server.password,
                                               persistence: .forSession)
            URLCredentialStorage.shared.set(userCredential, for: protectionSpace)
        }

        let request = URLRequest(url: url)
        let startDatetime = Date()
        modelData.logStartCalibreActivity(type: "List Libraries", request: request, startDatetime: startDatetime, bookId: nil, libraryId: nil)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer {
                modelData.logFinishCalibreActivity(type: "List Libraries", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: serverInfo.errorMsg)
                
                DispatchQueue.main.async {
                    modelData.calibreServerInfo = serverInfo
                    modelData.calibreServerUpdatingStatus = serverInfo.errorMsg
                    modelData.calibreServerUpdating = false
                }
            }
            if let error = error {
                serverInfo.errorMsg = error.localizedDescription
                return
            }
            var dataAsString = ""
            if let data = data, let s = String(data: data, encoding: .utf8) {
                dataAsString = s
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                serverInfo.errorMsg = dataAsString + response.debugDescription
                return
            }
            guard httpResponse.statusCode != 401 else {
                serverInfo.errorMsg = httpResponse.statusCode.description
                    + " " + HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                    + " " + dataAsString
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                serverInfo.errorMsg = httpResponse.statusCode.description
                    + " " + HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                    + " " + dataAsString
                return
            }
            guard let mimeType = httpResponse.mimeType, mimeType == "application/json",
                  let data = data,
                  let libraryInfo = try? JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary else {
                serverInfo.errorMsg = "Failed to parse server response"
                return
            }

            guard let libraryMap = libraryInfo["library_map"] as? [String: String] else {
                serverInfo.errorMsg = "No library info found in server response"
                return
            }
            defaultLog.info("libraryInfo: \(libraryInfo)")

            let defaultLibrary = libraryInfo["default_library"] as? String ?? ""

            serverInfo.defaultLibrary = defaultLibrary
            serverInfo.libraryMap = libraryMap
            serverInfo.reachable = true

            serverInfo.errorMsg = "Success"
        }

        modelData.calibreServerUpdating = true

        setCredential(server: server, task: task)

        task.resume()
    }
    
    func syncLibrary(server: CalibreServer, library: CalibreLibrary, alertDelegate: AlertDelegate) {
        guard let serverUrl = getServerUrlByReachability(server: server) else {
            modelData.calibreServerUpdatingStatus = "Server not Reachable"
            return
        }
        
        var urlComponents = URLComponents()
        
        urlComponents.path = "cdb/cmd/list/0"
        urlComponents.query = "library_id=\(library.key)"
        
//        guard let libraryKeyEncoded = library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
//              let endpointUrl = URL(string: server.serverUrl + "/cdb/cmd/list/0?library_id=" + libraryKeyEncoded)
//              else {
//            return
//        }
        
        guard let endpointUrl = urlComponents.url(relativeTo: serverUrl) else {
            modelData.calibreServerUpdatingStatus = "Internal Error"
            return
        }
        
        let json:[Any] = [["title", "authors", "formats", "rating", "series", "series_index", "identifiers"], "", "", "", -1]
        
        let data = try! JSONSerialization.data(withJSONObject: json, options: [])
        
        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "POST"
        request.httpBody = data
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let startDatetime = Date()
        modelData.logStartCalibreActivity(type: "Sync Library Books", request: request, startDatetime: startDatetime, bookId: nil, libraryId: library.id)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer {
                modelData.logFinishCalibreActivity(type: "Sync Library Books", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: updatingStatus)
            }
            var updatingStatus = "Failed"
            
            if let error = error {
                self.defaultLog.warning("error: \(error.localizedDescription)")

                let alertItem = AlertItem(id: error.localizedDescription, action: {
                    modelData.calibreServerUpdating = false
                    modelData.calibreServerUpdatingStatus = "Failed"
                })
                alertDelegate.alert(alertItem: alertItem)

                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                self.defaultLog.warning("not httpResponse: \(response.debugDescription)")
                
                let alertItem = AlertItem(id: response?.description ?? "nil reponse", action: {
                    modelData.calibreServerUpdating = false
                    modelData.calibreServerUpdatingStatus = "Failed"
                })
                alertDelegate.alert(alertItem: alertItem)
                
                return
            }
            
            if let mimeType = httpResponse.mimeType, mimeType == "application/json",
               let data = data {
                defer {
                    DispatchQueue.main.async {
                        modelData.calibreServerUpdating = false
                        modelData.calibreServerUpdatingStatus = updatingStatus

                        modelData.calibreServerLibraryUpdating = false
                    }
                }
                guard let resultBooks = self.handleLibraryBooks(library: library, json: data) else {
                    let alertItem = AlertItem(id: "Failed to parse calibre server response.")
                    alertDelegate.alert(alertItem: alertItem)
                    return
                }
            
                print("syncLibrary count=\(resultBooks.count)")
                
                modelData.updateBooks(books: resultBooks.map{$1})
                
                updatingStatus = "Refreshed"
            
                DispatchQueue.main.async {
                    modelData.calibreServerLibraryBooks = resultBooks
                    modelData.updateFilteredBookList()
                }
                
            }
        }
        
        modelData.calibreServerUpdating = true
        modelData.calibreServerUpdatingStatus = "Refreshing"
        
        setCredential(server: server, task: task)
        task.resume()
    }
    
    func syncLibraryPublisher(resultPrev: CalibreCustomColumnInfoResult, filter: String = "") -> AnyPublisher<CalibreCustomColumnInfoResult, Never> {
        guard let serverUrl = getServerUrlByReachability(server: resultPrev.library.server) else {
            var result = resultPrev
            result.errmsg = "Server not Reachable"
            return Just(result).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        guard var urlComponents = URLComponents(string: serverUrl.absoluteString) else {
            var result = resultPrev
            result.errmsg = "Internal Error"
            return Just(result).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        urlComponents.path = "/cdb/cmd/list/0"
        urlComponents.queryItems = [URLQueryItem(name: "library_id", value: resultPrev.library.key)]
        
        guard let endpointUrl = urlComponents.url(relativeTo: serverUrl) else {
            var result = resultPrev
            result.errmsg = "Internal Error"
            return Just(result).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        let json:[Any] = [["title", "authors", "formats", "rating", "series", "series_index", "identifiers", "last_modified", "timestamp", "pubdate", "tags"], "last_modified", "ascending", filter, -1]
        
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else {
            var result = resultPrev
            result.errmsg = "Query Error"
            return Just(result).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        let urlSessionConfiguration = URLSessionConfiguration.default
        urlSessionConfiguration.timeoutIntervalForRequest = 600
        let urlSessionDelegate = CalibreServerTaskDelegate(resultPrev.library.server.username)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: nil)

        var urlRequest = URLRequest(url: endpointUrl)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = data
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.addValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        
        let startDatetime = Date()
        modelData.logStartCalibreActivity(type: "Sync Library Books", request: urlRequest, startDatetime: startDatetime, bookId: nil, libraryId: resultPrev.library.id)

        let a = urlSession.dataTaskPublisher(for: urlRequest)
            .tryMap { output in
                // print("\(#function) \(output.response.debugDescription) \(output.data.debugDescription)")
                guard let response = output.response as? HTTPURLResponse, response.statusCode == 200 else {
                    print("\(#function) error \(resultPrev.library.id)")
                    throw NSError(domain: "HTTP", code: 0, userInfo: nil)
                }
                
                return output.data
            }
            .decode(type: [String: CalibreCdbCmdListResult].self, decoder: JSONDecoder())
            .replaceError(with: ["result": CalibreCdbCmdListResult(book_ids: [-1])])
            .map { listResult -> CalibreCustomColumnInfoResult in
                var result = resultPrev
                if let list = listResult["result"] {
                    result.list = list
                }
                return result
            }
            .eraseToAnyPublisher()
        
        return a
    }
    
    /**
     run on background threads, call completionHandler on main thread
     */
    func handleLibraryBooks(library: CalibreLibrary, json: Data) -> [Int32:CalibreBook]? {
        DispatchQueue.main.async {
            modelData.calibreServerLibraryUpdating = true
            modelData.calibreServerLibraryUpdatingTotal = 0
            modelData.calibreServerLibraryUpdatingProgress = 0
        }
        
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
            return nil
        }
        
        var calibreServerLibraryBooks = modelData.calibreServerLibraryBooks
        
        let resultElement = root["result"] as! NSDictionary
        let bookIds = resultElement["book_ids"] as! NSArray
        
        bookIds.forEach { idNum in
            let id = (idNum as! NSNumber).int32Value
            if calibreServerLibraryBooks[id] == nil {
                calibreServerLibraryBooks[id] = CalibreBook(id: id, library: library)
            }
        }
        
        let bookCount = calibreServerLibraryBooks.count
        DispatchQueue.main.async {
            modelData.calibreServerLibraryUpdatingTotal = bookCount
        }
        
        let dataElement = resultElement["data"] as! NSDictionary
        
        let titles = dataElement["title"] as! NSDictionary
        titles.forEach { (key, value) in
            let id = (key as! NSString).intValue
            let title = value as! String
            calibreServerLibraryBooks[id]!.title = title
        }
        
        let authors = dataElement["authors"] as! NSDictionary
        authors.forEach { (key, value) in
            let id = (key as! NSString).intValue
            let authors = value as! NSArray
            calibreServerLibraryBooks[id]!.authors = authors.compactMap({ (author) -> String? in
                author as? String
            })
        }
        
        let formats = dataElement["formats"] as! NSDictionary
        formats.forEach { (key, value) in
            let id = (key as! NSString).intValue
            let formats = value as! NSArray
            formats.forEach { format in
                calibreServerLibraryBooks[id]!.formats[(format as! String)] = FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)
            }
        }
        
        if let identifiers = dataElement["identifiers"] as? NSDictionary {
            identifiers.forEach { (key, value) in
                let id = (key as! NSString).intValue
                if let idDict = value as? NSDictionary {
                    calibreServerLibraryBooks[id]!.identifiers = idDict as! [String: String]
                }
            }
        }
        
        let ratings = dataElement["rating"] as! NSDictionary
        ratings.forEach { (key, value) in
            let id = (key as! NSString).intValue
            if let rating = value as? NSNumber {
                calibreServerLibraryBooks[id]!.rating = rating.intValue
            }
        }
        
        let series = dataElement["series"] as! NSDictionary
        series.forEach { (key, value) in
            let id = (key as! NSString).intValue
            if let series = value as? String {
                calibreServerLibraryBooks[id]!.series = series
            } else {
                calibreServerLibraryBooks[id]!.series = ""
            }
        }
        
        (dataElement["series_index"] as? NSDictionary)?.forEach { (key, value) in
            guard let id = (key as? NSString)?.intValue else { return }
            calibreServerLibraryBooks[id]?.seriesIndex = value as? Double ?? 0.0
        }
        
        return calibreServerLibraryBooks
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

        let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
            var updatingMetadataStatus = "Unknonwn Error"
            var bookResult = oldbook
            defer {
                modelData.logFinishCalibreActivity(type: "Get Book Metadata", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: updatingMetadataStatus)
                
                DispatchQueue.main.async {
                    modelData.updatingMetadataStatus = updatingMetadataStatus
                    modelData.updatingMetadata = false
                    
                    if updatingMetadataStatus == "Success" {
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
                updatingMetadataStatus = httpResponse.debugDescription
                return
            }
            
            guard let mimeType = httpResponse.mimeType, mimeType == "application/json",
                  let data = data,
                  let string = String(data: data, encoding: .utf8) else {
                updatingMetadataStatus = httpResponse.debugDescription
                return
            }
            
                
            guard var newbook = handleLibraryBookOne(oldbook: oldbook, json: data) else {
                updatingMetadataStatus = "Failed to Parse Calibre Server Response."
                return
            }
            
            if( newbook.readPos.getDevices().isEmpty) {
                let pair = modelData.defaultReaderForDefaultFormat(book: newbook)
                newbook.readPos.addInitialPosition(
                    modelData.deviceName,
                    pair.1.rawValue
                )
            }
                
            updatingMetadataStatus = "Success"
                
            bookResult = newbook
        }
        
        modelData.updatingMetadata = true
        
        setCredential(server: oldbook.library.server, task: task)
        task.resume()
    }
    
    func handleLibraryBookOne(oldbook: CalibreBook, json: Data) -> CalibreBook? {
        let decoder = JSONDecoder()
        
        guard let entry = try? decoder.decode(CalibreBookEntry.self, from: json),
              let root = try? JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
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
           let readPosData = Data(base64Encoded: readPosString),
           let readPosDictNew = try? decoder.decode([String:[String:BookDeviceReadingPosition]].self, from: readPosData),
           //let readPosDict = try? JSONSerialization.jsonObject(with: readPosData, options: []) as? NSDictionary,
           //let deviceMapDict = readPosDict["deviceMap"] as? NSDictionary {
           let deviceMapDict = readPosDictNew["deviceMap"] {
            
            deviceMapDict.forEach { key, value in
                let deviceName = key// as! String
                
                if deviceName == modelData.deviceName && modelData.getDeviceReadingPosition(book: book) != nil {
                    //ignore server, trust local record
                    return
                }
                
                var deviceReadingPosition = value
                deviceReadingPosition.id = deviceName
                
                book.readPos.updatePosition(deviceName, deviceReadingPosition)
                
                defaultLog.info("book.readPos.getDevices().count \(book.readPos.getDevices().count)")
            }
        }

        return book
    }
    
    func handleLibraryBookOne(library: CalibreLibrary, bookRealm: CalibreBookRealm, entry: CalibreBookEntry, root: NSDictionary) {
        let decoder = JSONDecoder()
//
//        guard let entry = try? decoder.decode(CalibreBookEntry.self, from: json),
//              let root = try? JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
//            print("\(#function) decode error \(String(describing: bookRealm.primaryKey))")
//            return
//        }
        
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
        var readPos = bookRealm.readPos()
        //Parse Reading Position
        if let pluginReadingPosition = modelData.calibreLibraries[library.id]?.pluginReadingPositionWithDefault, pluginReadingPosition.isEnabled(),
           let readPosString = userMetadatas[pluginReadingPosition.readingPositionCN.trimmingCharacters(in: CharacterSet(["#"]))] as? String,
           let readPosData = Data(base64Encoded: readPosString),
           let readPosDictNew = try? decoder.decode([String:[String:BookDeviceReadingPosition]].self, from: readPosData),
           //let readPosDict = try? JSONSerialization.jsonObject(with: readPosData, options: []) as? NSDictionary,
           //let deviceMapDict = readPosDict["deviceMap"] as? NSDictionary {
           let deviceMapDict = readPosDictNew["deviceMap"] {
            
            deviceMapDict.forEach { key, value in
                let deviceName = key// as! String
                
                if deviceName == modelData.deviceName && readPos.getPosition(deviceName) != nil {
                    //ignore server, trust local record
                    return
                }
                
                var deviceReadingPosition = value
                deviceReadingPosition.id = deviceName
                
                readPos.updatePosition(deviceName, deviceReadingPosition)
            }
            
            if let deviceMapSerialize = try? deviceMapDict.compactMapValues({ try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }) {
                bookRealm.readPosData = try? JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []) as NSData
            }
        }
    }
        
    
    func getBookManifest(book: CalibreBook, format: Format, completion: ((_ manifest: Data?) -> Void)? = nil) {
        let endpointUrl = URL(string: book.library.server.serverUrl + "/book-manifest/\(book.id)/\(format.id)?library_id=" + book.library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!

        let request = URLRequest(url: endpointUrl)
        
        let startDatetime = Date()
        modelData.logStartCalibreActivity(type: "Get Book Manifest", request: request, startDatetime: startDatetime, bookId: book.id, libraryId: book.library.id)

        let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
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

        setCredential(server: book.library.server, task: task)
        task.resume()
    }
    
    ///metadata: [[key1, value1], [key2, value2], ...]
    func updateMetadata(library: CalibreLibrary, bookId: Int32, metadata: [Any]) -> Int {
        guard var endpointURLComponent = URLComponents(string: library.server.serverUrl) else {
            return -1
        }
        
        endpointURLComponent.path = "/cdb/cmd/set_metadata/0"
        endpointURLComponent.query = "library_id=\(library.name)"
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

        let updatingMetadataTask = URLSession.shared.dataTask(with: request) { [self] data, response, error in
            print("\(#function) \(data) \(response) \(error)")
            modelData.logFinishCalibreActivity(type: "Set Book Metadata", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: "Finished")
        }
        
        setCredential(server: library.server, task: updatingMetadataTask)
        updatingMetadataTask.resume()
        
        return 0
    }
    
    func updateBookReadingPosition(book: CalibreBook, columnName: String, alertDelegate: AlertDelegate, success: (() -> Void)?) -> Int {
        guard var endpointURLComponent = URLComponents(string: book.library.server.serverUrl) else {
            return -1
        }
        
        endpointURLComponent.path = "/cdb/cmd/set_metadata/0"
        endpointURLComponent.query = "library_id=\(book.library.name)"
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
        
        let updatingMetadataTask = URLSession.shared.dataTask(with: request) { [self] data, response, error in
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
                        alertDelegate.alert(msg: updatingMetadataStatus)
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
        
        setCredential(server: book.library.server, task: updatingMetadataTask)
        updatingMetadataTask.resume()
        
        return 0
    }
    
    /// read-modify-write version
    func updateBookReadingPositionNew(book: CalibreBook, columnName: String, alertDelegate: AlertDelegate, success: (() -> Void)?) -> Int {
        
        guard let task = buildMetadataTask(book: book) else { return -1 }
        
        modelData.calibreServiceCancellable = getMetadataNew(task: task)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in
                
            }, receiveValue: { (task, data, urlResponse) in
                guard var newBook = handleLibraryBookOne(oldbook: book, json: data) else { return }
                guard let newPosition = book.readPos.getPosition(modelData.deviceName) else { return }
                newBook.readPos.updatePosition(modelData.deviceName, newPosition)
                modelData.updateBook(book: newBook)
                
                _ = updateBookReadingPosition(book: newBook, columnName: columnName, alertDelegate: alertDelegate, success: success)
            })

        return 0
    }

    func setCredential(server: CalibreServer, task: URLSessionDataTask) {
        if let protectionSpace = getProtectionSpace(server: server, port: nil),
            let credential = URLCredentialStorage.shared.credentials(for: protectionSpace)?[server.username] {
            URLCredentialStorage.shared.setDefaultCredential(credential, for: protectionSpace, task: task)
        }
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
    
    func probeServerReachability(server: CalibreServer, isPublic: Bool) {
        let infoId = server.id + " " + isPublic.description
        guard var serverInfo = modelData.calibreServerInfoStaging[infoId] else { return }

        serverInfo.reachable = false
        serverInfo.errorMsg = "Unknown Error"
        serverInfo.probingTask?.cancel()
        
        guard var url = URL(string: isPublic ? server.publicUrl : server.baseUrl), let host = url.host else {
            modelData.calibreServerInfoStaging[infoId] = serverInfo
            return
        }
        url.appendPathComponent("/ajax/library-info", isDirectory: false)
        
        if server.username.count > 0 && server.password.count > 0 {
            var authMethod = NSURLAuthenticationMethodDefault
            if url.scheme == "http" {
                authMethod = NSURLAuthenticationMethodHTTPDigest
            }
            if url.scheme == "https" {
                authMethod = NSURLAuthenticationMethodHTTPBasic
            }
            let protectionSpace = URLProtectionSpace.init(host: host,
                                                          port: url.port ?? 0,
                                                          protocol: url.scheme,
                                                          realm: "calibre",
                                                          authenticationMethod: authMethod)
            let userCredential = URLCredential(user: server.username,
                                               password: server.password,
                                               persistence: .permanent)
            URLCredentialStorage.shared.set(userCredential, for: protectionSpace)
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            defer {
                print("probeServerReachability \(serverInfo)")
                DispatchQueue.main.async {
                    modelData.calibreServerInfoStaging[serverInfo.id] = serverInfo
                }
            }
            if let error = error {
                serverInfo.errorMsg = error.localizedDescription
                return
            }
            var dataAsString = ""
            if let data = data, let s = String(data: data, encoding: .utf8) {
                dataAsString = s
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                serverInfo.errorMsg = dataAsString + response.debugDescription
                return
            }
            guard httpResponse.statusCode != 401 else {
                serverInfo.errorMsg = httpResponse.statusCode.description
                    + " " + HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                    + " " + dataAsString
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                serverInfo.errorMsg = httpResponse.statusCode.description
                    + " " + HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                    + " " + dataAsString
                return
            }
            guard let mimeType = httpResponse.mimeType, mimeType == "application/json",
                  let data = data,
                  let libraryInfo = try? JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary else {
                serverInfo.errorMsg = "Failed to parse server response"
                return
            }

            guard let libraryMap = libraryInfo["library_map"] as? [String: String] else {
                serverInfo.errorMsg = "No library info found in server response"
                return
            }
            defaultLog.info("libraryInfo: \(libraryInfo)")


            let defaultLibrary = libraryInfo["default_library"] as? String ?? ""

            serverInfo.defaultLibrary = defaultLibrary
            serverInfo.libraryMap = libraryMap
            serverInfo.reachable = true
            serverInfo.errorMsg = "Success"
        }

        setCredential(server: server, task: task)

        serverInfo.probingTask = task
        task.resume()
    }
    
    // MARK: - Combine style below
    
    func probeServerReachabilityNew(serverInfo: CalibreServerInfo) -> AnyPublisher<(String, CalibreServerLibraryInfo), Never> {
        var serverInfo = serverInfo
        
        serverInfo.reachable = false
        serverInfo.errorMsg = "Unknown Error"
        serverInfo.probingTask?.cancel()
        
        var url = serverInfo.url
        url.appendPathComponent("/ajax/library-info", isDirectory: false)
        let urlSessionConfiguration = URLSessionConfiguration.default
        urlSessionConfiguration.timeoutIntervalForRequest = 10
        let urlSessionDelegate = CalibreServerTaskDelegate(serverInfo.server.username)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: nil)
        
        return urlSession.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: CalibreServerLibraryInfo.self, decoder: JSONDecoder())
            .replaceError(with: CalibreServerLibraryInfo(defaultLibrary: nil, libraryMap: [:]))
            .map { (serverInfo.id, $0) }
            .eraseToAnyPublisher()
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
            bookId: bookId,
            inShelfId: "",
            url: endpointUrl, username: library.server.username)
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
            bookId: book.id,
            inShelfId: book.inShelfId,
            url: endpointUrl, username: book.library.server.username)
    }
    
    func buildBooksMetadataTask(library: CalibreLibrary, books: [String]) -> CalibreBooksTask? {
        guard let serverUrl = getServerUrlByReachability(server: library.server) else {
            return nil
        }
        var urlComponents = URLComponents()
        urlComponents.path = "/ajax/books/\(library.key)"
        urlComponents.queryItems = [
            URLQueryItem(name: "ids", value: books.joined(separator: ","))
        ]
        guard let endpointUrl = urlComponents.url(relativeTo: serverUrl)?.absoluteURL else {
            return nil
        }
        
        return CalibreBooksTask(
            library: library,
            books: books,
            url: endpointUrl
        )
    }
    
    func getMetadata(task: CalibreBookTask) -> AnyPublisher<(CalibreBookTask, CalibreBookEntry), Never> {
        let urlSessionConfiguration = URLSessionConfiguration.default
        let urlSessionDelegate = CalibreServerTaskDelegate(task.username)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: nil)
        
        return urlSession.dataTaskPublisher(for: task.url)
            .map { $0.data }
            .decode(type: CalibreBookEntry.self, decoder: JSONDecoder())
            .replaceError(with: CalibreBookEntry())
            .map { (task, $0) }
            .eraseToAnyPublisher()
    }
    
    func getMetadataNew(task: CalibreBookTask) -> AnyPublisher<(CalibreBookTask, Data, URLResponse), URLError> {
        let urlSessionConfiguration = URLSessionConfiguration.default
        let urlSessionDelegate = CalibreServerTaskDelegate(task.username)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: modelData.metadataQueue)
        
        let a = urlSession.dataTaskPublisher(for: task.url)
            .map { (task, $0.data, $0.response) }
            .eraseToAnyPublisher()
        return a
    }
    
    func getBooksMetadata(task: CalibreBooksTask) -> AnyPublisher<CalibreBooksTask, URLError> {
        let urlSessionConfiguration = URLSessionConfiguration.default
        urlSessionConfiguration.timeoutIntervalForRequest = 600
        let urlSessionDelegate = CalibreServerTaskDelegate(task.library.server.username)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: modelData.metadataQueue)
        
        let a = urlSession.dataTaskPublisher(for: task.url)
            .map { result -> CalibreBooksTask in
                var task = task
                task.data = result.data
                task.response = result.response
                return task
            }
            .eraseToAnyPublisher()
        return a
    }
    
    func setLastReadPosition(book: CalibreBook, format: Format, position: BookDeviceReadingPosition) -> Int {
        
        guard var endpointURLComponent = URLComponents(string: book.library.server.serverUrl) else {
            return -1
        }
        
        endpointURLComponent.path = "/book-set-last-read-position/\(book.library.key)/\(book.id)/\(format.rawValue)"
        guard let endpointUrl = endpointURLComponent.url else {
            return -1
        }
        
        let entry = CalibreBookLastReadPositionEntry(device: position.id, cfi: position.cfi, epoch: position.epoch, pos_frac: position.lastProgress / 100)
        guard let postData = try? JSONEncoder().encode(entry) else {
            return -2
        }
        let urlSessionConfiguration = URLSessionConfiguration.default
        let urlSessionDelegate = CalibreServerTaskDelegate(book.library.server.username)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: nil)
        
        var urlRequest = URLRequest(url: endpointUrl)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = postData
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")

        modelData.calibreServiceCancellable = urlSession.dataTaskPublisher(for: urlRequest)
            .tryMap { output in
                print("setLastReadPosition \(output.response.debugDescription) \(output.data.debugDescription)")
                guard let response = output.response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw NSError(domain: "HTTP", code: 0, userInfo: nil)
                }
                
                return output.data
            }
            .decode(type: [String: [CalibreBookLastReadPositionEntry]].self, decoder: JSONDecoder())
            .replaceError(with: [:])
            .eraseToAnyPublisher()
            .sink(
                receiveCompletion: { completion in
                    print("setLastReadPosition \(completion)")
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        fatalError(error.localizedDescription)
                    }
                },
                receiveValue: { results in
                    print("setLastReadPosition count=\(results.count)")
                    results.forEach { result in
                        print("setLastReadPosition \(result)")
                    }
                }
            )
        
        return 0
    }
    
    func getLastReadPosition(book: CalibreBook, formats: [Format]) -> Int {
        guard formats.isEmpty == false,
              var endpointURLComponent = URLComponents(string: book.library.server.serverUrl) else {
            return -1
        }
        
        let which = formats.map { "\(book.id)-\($0.rawValue)" }.joined(separator: "_")
        
        endpointURLComponent.path = "/book-get-last-read-position/\(book.library.key)/\(which)"
        guard let endpointUrl = endpointURLComponent.url else {
            return -1
        }
        
        let urlSessionConfiguration = URLSessionConfiguration.default
        let urlSessionDelegate = CalibreServerTaskDelegate(book.library.server.username)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: nil)
        
        modelData.calibreServiceCancellable = urlSession.dataTaskPublisher(for: endpointUrl)
            .tryMap { output in
                print("getLastReadPosition \(output.response.debugDescription) \(output.data.debugDescription)")
                guard let response = output.response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw NSError(domain: "HTTP", code: 0, userInfo: nil)
                }
                
                return output.data
            }
            .decode(type: [String: [CalibreBookLastReadPositionEntry]].self, decoder: JSONDecoder())
            .replaceError(with: [:])
            .eraseToAnyPublisher()
            .sink(
                receiveCompletion: { completion in
                    print("getLastReadPosition \(completion)")
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        fatalError(error.localizedDescription)
                    }
                },
                receiveValue: { results in
                    print("getLastReadPosition count=\(results.count)")
                    results.forEach { result in
                        print("getLastReadPositionResult \(result)")
                    }
                }
            )
        
        return 0
    }
    
    func updateAnnotations(book: CalibreBook, format: Format, highlights: [CalibreBookAnnotationEntry]) -> Int {
        guard highlights.isEmpty == false,
              var endpointURLComponent = URLComponents(string: book.library.server.serverUrl) else {
            return -1
        }

        endpointURLComponent.path = "/book-update-annotations/\(book.library.key)/\(book.id)/\(format.rawValue)"
        guard let endpointUrl = endpointURLComponent.url else {
            return -1
        }

        let entry = ["\(book.id):\(format.rawValue)":highlights]
        guard let postData = try? JSONEncoder().encode(entry) else {
            return -2
        }
        let urlSessionConfiguration = URLSessionConfiguration.default
        let urlSessionDelegate = CalibreServerTaskDelegate(book.library.server.username)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: nil)

        var urlRequest = URLRequest(url: endpointUrl)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = postData
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")

        let startDatetime = Date()
        modelData.logStartCalibreActivity(type: "Update Annotations", request: urlRequest, startDatetime: startDatetime, bookId: book.id, libraryId: book.library.id)

        modelData.calibreServiceCancellable = urlSession.dataTaskPublisher(for: urlRequest)
            .tryMap { output in
                print("updateAnnotations \(output.response.debugDescription) \(output.data.debugDescription)")
                guard let response = output.response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw NSError(domain: "HTTP", code: 0, userInfo: nil)
                }

                return output.data
            }
            .decode(type: [String: [CalibreBookLastReadPositionEntry]].self, decoder: JSONDecoder())
            .replaceError(with: [:])
            .eraseToAnyPublisher()
            .sink(
                receiveCompletion: { completion in
                    print("updateAnnotations \(completion)")
                    switch completion {
                    case .finished:
                        modelData.logFinishCalibreActivity(type: "Update Annotations", request: urlRequest, startDatetime: startDatetime, finishDatetime: Date(), errMsg: "Empty Result")
                        break
                    case .failure(let error):
                        modelData.logFinishCalibreActivity(type: "Update Annotations", request: urlRequest, startDatetime: startDatetime, finishDatetime: Date(), errMsg: error.localizedDescription)
                        break
                    }
                },
                receiveValue: { results in
                    print("updateAnnotations count=\(results.count)")
                    results.forEach { result in
                        print("updateAnnotations \(result)")
                    }
                    modelData.logFinishCalibreActivity(type: "Update Annotations", request: urlRequest, startDatetime: startDatetime, finishDatetime: Date(), errMsg: "Updated")
                }
            )

        return 0
    }
    
    func getAnnotations(book: CalibreBook, formats: [Format]) -> Int {
        guard formats.isEmpty == false,
              var endpointURLComponent = URLComponents(string: book.library.server.serverUrl) else {
            return -1
        }
        
        let which = formats.map { "\(book.id)-\($0.rawValue)" }.joined(separator: "_")
        
        endpointURLComponent.path = "/book-get-annotations/\(book.library.key)/\(which)"
        guard let endpointUrl = endpointURLComponent.url else {
            return -1
        }
        
        /*
         {
           "6:EPUB": {
             "last_read_positions": [
               {
                 "device": "Mine",
                 "cfi": "/2/4/2/2/2/2/4/2/8/2/1:105",
                 "epoch": 1630591286.91118,
                 "pos_frac": 0.1
               },
               {
                 "device": "iPad Pro (11-inch) (3rd generation)",
                 "cfi": "/12/4/2/4",
                 "epoch": 1630818264.6980531,
                 "pos_frac": 0.1923076923076923
               }
             ],
             "annotations_map": {
               "highlight": [
                 {
                   "end_cfi": "/2/4/2/2/2/2/4/2/8/2/1:134",
                   "highlighted_text": "但愿在讨论这个令人感兴趣的问题时，激励我的只是对真理的热爱",
                   "spine_index": 4,
                   "spine_name": "populationch00.html",
                   "start_cfi": "/2/4/2/2/2/2/4/2/8/2/1:105",
                   "style": {
                     "kind": "color",
                     "type": "builtin",
                     "which": "yellow"
                   },
                   "timestamp": "2021-09-01T06:22:52.491Z",
                   "toc_family_titles": [
                     "序"
                   ],
                   "type": "highlight",
                   "uuid": "bXNJ7u7JhxE2k-CxAURl4A"
                 }
               ]
             }
           }
         }
         */
        
        let urlSessionConfiguration = URLSessionConfiguration.default
        let urlSessionDelegate = CalibreServerTaskDelegate(book.library.server.username)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: nil)
        
        modelData.calibreServiceCancellable = urlSession.dataTaskPublisher(for: endpointUrl)
            .tryMap { output in
                print("getAnnotations \(output.response.debugDescription) \(output.data.debugDescription)")
                guard let response = output.response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw NSError(domain: "HTTP", code: 0, userInfo: nil)
                }
                
                return output.data
            }
            .decode(type: [String: CalibreBookAnnotationsResult].self, decoder: JSONDecoder())
            .replaceError(with: [:])
            .eraseToAnyPublisher()
            .sink(
                receiveCompletion: { completion in
                    print("getAnnotations \(completion)")
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        break
                    }
                },
                receiveValue: { results in
                    print("getAnnotations count=\(results.count)")
                    formats.forEach { format in
                        guard let result = results["\(book.id):\(format.rawValue)"] else { return }
                        print("getAnnotations \(result)")
                        if let highlightResult = result.annotations_map["highlight"],
                            let realmConfig = getBookPreferenceConfig(book: book, format: format),
                            let bookId = realmConfig.fileURL?.deletingPathExtension().lastPathComponent {
                            let highlightProvider = FolioReaderRealmHighlightProvider(realmConfig: realmConfig)
                            highlightProvider.folioReaderHighlight(bookId: bookId, added: highlightResult)
                        }
                    }
                }
            )
        
        return 0
    }
    
    func getCustomColumnsPublisher(library: CalibreLibrary) -> AnyPublisher<CalibreCustomColumnInfoResult, Never> {
        let error: [String: [String:CalibreCustomColumnInfo]] = ["error":[:]]

        guard let serverURL = getServerUrlByReachability(server: library.server),
              var endpointURLComponent = URLComponents(string: serverURL.absoluteString) else {
            return Just(CalibreCustomColumnInfoResult(library: library, result: error)).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        endpointURLComponent.path.append("/cdb/cmd/custom_columns/0")
        endpointURLComponent.queryItems = [URLQueryItem(name: "library_id", value: library.key)]

        guard let endpointUrl = endpointURLComponent.url else {
            return Just(CalibreCustomColumnInfoResult(library: library, result: error)).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        
        guard let postData = "[]".data(using: .utf8) else {
            return Just(CalibreCustomColumnInfoResult(library: library, result: error)).setFailureType(to: Never.self).eraseToAnyPublisher()
        }
        let urlSessionConfiguration = URLSessionConfiguration.default
        let urlSessionDelegate = CalibreServerTaskDelegate(library.server.username)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: nil)

        var urlRequest = URLRequest(url: endpointUrl)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = postData
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")

        let a = urlSession.dataTaskPublisher(for: urlRequest)
            .tryMap { output in
                print("\(#function) \(output.response.debugDescription) \(output.data.debugDescription)")
                guard let response = output.response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw NSError(domain: "HTTP", code: 0, userInfo: nil)
                }
                
                return output.data
            }
            .decode(type: [String: [String:CalibreCustomColumnInfo]].self, decoder: JSONDecoder())
            .replaceError(with: error)
            .map {
                CalibreCustomColumnInfoResult(library: library, result: $0)
            }
            .eraseToAnyPublisher()
        
        return a
    }
    
    func getCustomColumns(library: CalibreLibrary, completion: (([String: CalibreCustomColumnInfo]) -> Void)? = nil) -> Int {
        guard let serverURL = getServerUrlByReachability(server: library.server),
              var endpointURLComponent = URLComponents(string: serverURL.absoluteString) else {
            return -1
        }
        
        endpointURLComponent.path.append("/cdb/cmd/custom_columns/0")
        endpointURLComponent.queryItems = [URLQueryItem(name: "library_id", value: library.key)]

        guard let endpointUrl = endpointURLComponent.url else {
            return -1
        }
        
        guard let postData = "[]".data(using: .utf8) else {
            return -2
        }
        let urlSessionConfiguration = URLSessionConfiguration.default
        let urlSessionDelegate = CalibreServerTaskDelegate(library.server.username)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: nil)

        var urlRequest = URLRequest(url: endpointUrl)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = postData
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")

        modelData.calibreServiceCancellable = urlSession.dataTaskPublisher(for: urlRequest)
            .tryMap { output in
                print("\(#function) \(output.response.debugDescription) \(output.data.debugDescription)")
                guard let response = output.response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw NSError(domain: "HTTP", code: 0, userInfo: nil)
                }
                
                return output.data
            }
            .decode(type: [String: [String:CalibreCustomColumnInfo]].self, decoder: JSONDecoder())
            .replaceError(with: [:])
            .eraseToAnyPublisher()
            .receive(on: DispatchQueue.main)
            .sink { results in
                print("\(#function) count=\(results.count) result=\(results)")
                completion?(results["result"] ?? [:])
            }
        
        return 0
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
    var reachable: Bool
    var errorMsg: String
    var probingTask: URLSessionDataTask?
    var defaultLibrary: String
    var libraryMap: [String:String]
}

class CalibreServerTaskDelegate: NSObject, URLSessionTaskDelegate {
    let username: String
    
    init(_ username: String) {
        self.username = username
    }
    
    func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                  didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.previousFailureCount < 3 else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        print("CalibreServerTaskDelegate \(task) \(challenge.previousFailureCount) \(challenge.protectionSpace)")
        
        let credentials = URLCredentialStorage.shared.credentials(for: challenge.protectionSpace)
        completionHandler(.useCredential, credentials?[username])
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
