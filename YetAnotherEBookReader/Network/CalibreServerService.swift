//
//  CalibreServerService.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/12.
//

import Foundation
import OSLog

struct CalibreServerService {
    var modelData: ModelData

    var defaultLog = Logger()

    func getServerLibraries(server: CalibreServer){
        modelData.calibreServerInfo = nil
        modelData.calibreServerUpdatingStatus = "Initializing"

        var serverInfo = CalibreServerInfo(server: server, isPublic: server.usePublic, reachable: false, errorMsg: "Server URL Malformed", defaultLibrary: "", libraryMap: [:])

        guard let serverUrl = getServerUrlByReachability(server: server) ?? URL(string: server.baseUrl) else {
            modelData.calibreServerInfo = serverInfo
            modelData.calibreServerUpdatingStatus = serverInfo.errorMsg
            return
        }
        
        var urlComponents = URLComponents()
        urlComponents.path = "ajax/library-info"
        
        guard let url = urlComponents.url(relativeTo: serverUrl) else {
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
            let protectionSpace = URLProtectionSpace.init(host: url.host!,
                                                          port: url.port ?? 0,
                                                          protocol: url.scheme,
                                                          realm: "calibre",
                                                          authenticationMethod: authMethod)
            let userCredential = URLCredential(user: server.username,
                                               password: server.password,
                                               persistence: .forSession)
            URLCredentialStorage.shared.set(userCredential, for: protectionSpace)
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            defer {
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
        
        let json:[Any] = [["title", "authors", "formats", "rating", "series", "identifiers"], "", "", "", -1]
        
        let data = try! JSONSerialization.data(withJSONObject: json, options: [])
        
        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "POST"
        request.httpBody = data
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
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
                var updatingStatus = "Failed"
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
        
        return calibreServerLibraryBooks
    }
    
    func getMetadataNew(oldbook: CalibreBook, completion: ((_ newbook: CalibreBook) -> Void)? = nil) {
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
        
        let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
            var updatingMetadataStatus = "Unknonwn Error"
            var bookResult = oldbook
            defer {
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
            
                
            guard var newbook = handleLibraryBookOneNew(oldbook: oldbook, json: data) else {
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
    
    func handleLibraryBookOneNew(oldbook: CalibreBook, json: Data) -> CalibreBook? {
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
            return nil
        }
        
        var book = oldbook
        if let v = root["title"] as? String {
            book.title = v
        }
        if let v = root["publisher"] as? String {
            book.publisher = v
        }
        if let v = root["series"] as? String {
            book.series = v
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime
        if let v = root["pubdate"] as? String, let date = dateFormatter.date(from: v) {
            book.pubDate = date
        }
        if let v = root["last_modified"] as? String, let date = dateFormatter.date(from: v) {
            book.lastModified = date
        }
        if let v = root["timestamp"] as? String, let date = dateFormatter.date(from: v) {
            book.timestamp = date
        }
        
        if let v = root["tags"] as? NSArray {
            book.tags = v.compactMap { (t) -> String? in
                t as? String
            }
        }
        
        if let v = root["format_metadata"] as? NSDictionary {
            book.formats = v.reduce(
                into: book.formats
            ) { result, format in
                if let fKey = format.key as? String,
                   let fVal = format.value as? NSDictionary,
                   let sizeVal = fVal["size"] as? NSNumber,
                   let mtimeVal = fVal["mtime"] as? String {
                    var formatInfo = result[fKey.uppercased()] ?? FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)
                    
                    formatInfo.serverSize = sizeVal.uint64Value
                    
                    let dateFormatter = ISO8601DateFormatter()
                    dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
                    if let mtime = dateFormatter.date(from: mtimeVal) {
                        formatInfo.serverMTime = mtime
                    }
                    
                    result[fKey.uppercased()] = formatInfo
                }
            }
        }
        
        book.size = 0   //parse later
        
        if let v = root["rating"] as? NSNumber {
            book.rating = v.intValue * 2
        }
        
        if let v = root["authors"] as? NSArray {
            book.authors = v.compactMap { (t) -> String? in
                t as? String
            }
        }

        if let v = root["identifiers"] as? NSDictionary {
            if let ids = v as? [String: String] {
                book.identifiers = ids
            }
        }
        
        if let v = root["comments"] as? String {
            book.comments = v
        }
        
        //Parse Reading Position
        if let readPosColumnName = modelData.calibreLibraries[oldbook.library.id]?.readPosColumnName,
              let userMetadata = root["user_metadata"] as? NSDictionary,
              let userMetadataReadPosDict = userMetadata[readPosColumnName] as? NSDictionary,
              let readPosString = userMetadataReadPosDict["#value#"] as? String,
              let readPosData = Data(base64Encoded: readPosString),
              let readPosDict = try? JSONSerialization.jsonObject(with: readPosData, options: []) as? NSDictionary,
              let deviceMapDict = readPosDict["deviceMap"] as? NSDictionary {
            deviceMapDict.forEach { key, value in
                let deviceName = key as! String
                
                if deviceName == modelData.deviceName && modelData.getDeviceReadingPosition(book: book) != nil {
                    //ignore server, trust local record
                    return
                }
                
                let deviceReadingPositionDict = value as! [String: Any]
                //TODO merge
                var deviceReadingPosition = BookDeviceReadingPosition(id: deviceName, readerName: deviceReadingPositionDict["readerName"] as! String)
                
                deviceReadingPosition.lastReadPage = deviceReadingPositionDict["lastReadPage"] as! Int
                deviceReadingPosition.lastReadChapter = deviceReadingPositionDict["lastReadChapter"] as! String
                deviceReadingPosition.lastChapterProgress = deviceReadingPositionDict["lastChapterProgress"] as? Double ?? 0.0
                deviceReadingPosition.lastProgress = deviceReadingPositionDict["lastProgress"] as? Double ?? 0.0
                deviceReadingPosition.furthestReadPage = deviceReadingPositionDict["furthestReadPage"] as! Int
                deviceReadingPosition.furthestReadChapter = deviceReadingPositionDict["furthestReadChapter"] as! String
                deviceReadingPosition.maxPage = deviceReadingPositionDict["maxPage"] as! Int
                if let lastPosition = deviceReadingPositionDict["lastPosition"] {
                    deviceReadingPosition.lastPosition = lastPosition as! [Int]
                }
                book.readPos.updatePosition(deviceName, deviceReadingPosition)
                
                defaultLog.info("book.readPos.getDevices().count \(book.readPos.getDevices().count)")
            }
        }
                
        return book
    }
    
    func getBookManifest(book: CalibreBook, format: Format, completion: ((_ manifest: Data?) -> Void)? = nil) {
        let endpointUrl = URL(string: book.library.server.serverUrl + "/book-manifest/\(book.id)/\(format.id)?library_id=" + book.library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!

        let request = URLRequest(url: endpointUrl)
        
        let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
            var updatingMetadataStatus = "Unknown Error"
            defer {
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
    
    func updateBookReadingPosition(book: CalibreBook, columnName: String, alertDelegate: AlertDelegate, success: (() -> Void)?) -> Int {
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
        
        guard var endpointURLComponent = URLComponents(string: book.library.server.serverUrl) else {
            return -1
        }
        
        endpointURLComponent.path = "/cdb/cmd/set_metadata/0"
        endpointURLComponent.query = "library_id=\(book.library.name)"
        guard let endpointUrl = endpointURLComponent.url else {
            return -1
        }
        
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
        
//        if updatingMetadata && updatingMetadataTask != nil {
//            updatingMetadataTask!.cancel()
//        }
        
        let updatingMetadataTask = URLSession.shared.dataTask(with: request) { [self] data, response, error in
            var updatingMetadataStatus = "Unknown Error"
            var newBook = book
            
            defer {
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
    
    func setCredential(server: CalibreServer, task: URLSessionDataTask) {
        guard server.username.count > 0 && server.password.count > 0 else { return }
        guard let url = task.originalRequest?.url,
              let host = url.host
        else { return }
        
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
        if let credentials = URLCredentialStorage.shared.credentials(for: protectionSpace),
           let credential = credentials.filter({ $0.key == server.username }).first?.value {
            URLCredentialStorage.shared.setDefaultCredential(credential, for: protectionSpace, task: task)
        }
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
        
        guard var url = URL(string: isPublic ? server.publicUrl : server.baseUrl) else {
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
            let protectionSpace = URLProtectionSpace.init(host: url.host!,
                                                          port: url.port ?? 0,
                                                          protocol: url.scheme,
                                                          realm: "calibre",
                                                          authenticationMethod: authMethod)
            let userCredential = URLCredential(user: server.username,
                                               password: server.password,
                                               persistence: .forSession)
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
}

struct CalibreServerInfo: Identifiable {
    var id: String {
        server.id + " " + isPublic.description
    }
    
    let server: CalibreServer
    let isPublic: Bool
    var reachable: Bool
    var errorMsg: String
    var probingTask: URLSessionDataTask?
    var defaultLibrary: String
    var libraryMap: [String:String]
}
