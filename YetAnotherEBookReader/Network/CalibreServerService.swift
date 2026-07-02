//
//  CalibreServerService.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/12.
//

import Foundation
import OSLog
import Combine

final class CalibreServerService {
    var logger: CalibreActivityLogger
    weak var config: AppContainerProtocol?
    var database: DatabaseService
    var defaultLog = Logger(subsystem: "io.github.dsreader", category: "CalibreServerService")
    var metadataSessions = [CalibreServerURLSessionKey: URLSession]()
    lazy var metadataQueue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Book Metadata queue"
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    
    private let sessionsQueue = DispatchQueue(label: "io.github.dsreader.CalibreServerService.sessions")
    
    private let configLock = NSRecursiveLock()
    private var _localDeviceName = ""
    private var _localCalibreLibraries = [String: CalibreLibrary]()
    private var _localCalibreServerInfoStaging = [String: CalibreServerInfo]()
    
    init(logger: CalibreActivityLogger, config: AppContainerProtocol, database: DatabaseService) {
        self.logger = logger
        self.config = config
        self.database = database
        
        self._localDeviceName = config.deviceName
        self._localCalibreLibraries = config.calibreLibraries
        self._localCalibreServerInfoStaging = config.calibreServerInfoStaging
    }
    
    // Mapping Computed Properties
    var updatingMetadataStatus: String {
        get { config?.updatingMetadataStatus ?? "" }
        set { config?.updatingMetadataStatus = newValue }
    }
    var updatingMetadata: Bool {
        get { config?.updatingMetadata ?? false }
        set { config?.updatingMetadata = newValue }
    }
    var updatingMetadataSucceed: Bool {
        get { config?.updatingMetadataSucceed ?? false }
        set { config?.updatingMetadataSucceed = newValue }
    }
    var librarySyncStatus: [String: CalibreSyncStatus] {
        get { config?.librarySyncStatus ?? [:] }
        set { config?.librarySyncStatus = newValue }
    }
    var deviceName: String {
        configLock.lock()
        defer { configLock.unlock() }
        if Thread.isMainThread {
            let val = config?.deviceName ?? ""
            _localDeviceName = val
            return val
        } else {
            return _localDeviceName
        }
    }
    var calibreLibraries: [String: CalibreLibrary] {
        configLock.lock()
        defer { configLock.unlock() }
        if Thread.isMainThread {
            let val = config?.calibreLibraries ?? [:]
            _localCalibreLibraries = val
            return val
        } else {
            return _localCalibreLibraries
        }
    }
    var calibreServerInfoStaging: [String: CalibreServerInfo] {
        configLock.lock()
        defer { configLock.unlock() }
        if Thread.isMainThread {
            let val = config?.calibreServerInfoStaging ?? [:]
            _localCalibreServerInfoStaging = val
            return val
        } else {
            return _localCalibreServerInfoStaging
        }
    }
    
    func updateServerInfoStaging(_ staging: [String: CalibreServerInfo]) {
        configLock.lock()
        defer { configLock.unlock() }
        self._localCalibreServerInfoStaging = staging
    }
    
    func updateCalibreLibraries(_ libraries: [String: CalibreLibrary]) {
        configLock.lock()
        defer { configLock.unlock() }
        self._localCalibreLibraries = libraries
    }
    
    func updateDeviceName(_ deviceName: String) {
        configLock.lock()
        defer { configLock.unlock() }
        self._localDeviceName = deviceName
    }
    
    // Mapping methods
    func updateBook(book: CalibreBook) {
        config?.updateBook(book: book)
    }
    func getPreferredFormat(for book: CalibreBook) -> Format? {
        config?.getPreferredFormat(for: book)
    }

    func urlSession(server: CalibreServer, timeout: Double = 600, qos: DispatchQoS.QoSClass = .default) -> URLSession {
        let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
        
        return sessionsQueue.sync {
            if let session = metadataSessions[key] {
                return session
            }
            let urlSessionConfiguration = URLSessionConfiguration.default
            urlSessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            urlSessionConfiguration.timeoutIntervalForRequest = timeout
            urlSessionConfiguration.httpMaximumConnectionsPerHost = 4
            let urlSessionDelegate = CalibreServerTaskDelegate(server)
            let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: metadataQueue)
            
            metadataSessions[key] = urlSession
            return urlSession
        }
    }

    func makeEndpointURL(server: CalibreServer, path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard let serverURL = getServerUrlByReachability(server: server) else {
            throw CalibreAPIError.serverUnreachable
        }

        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url(relativeTo: serverURL) else {
            throw CalibreAPIError.invalidURL(path)
        }
        return url
    }

    func makeJSONRequest(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json",
        accept: String = "application/json",
        acceptEncoding: String? = nil,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    ) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.httpMethod = method
        request.httpBody = body
        request.addValue(contentType, forHTTPHeaderField: "Content-Type")
        request.addValue(accept, forHTTPHeaderField: "Accept")
        if let acceptEncoding {
            request.addValue(acceptEncoding, forHTTPHeaderField: "Accept-Encoding")
        }
        return request
    }

    func validatedData(from url: URL, server: CalibreServer, timeout: Double = 600, qos: DispatchQoS.QoSClass = .default) async throws -> (Data, HTTPURLResponse) {
        try await validatedData(for: URLRequest(url: url), server: server, timeout: timeout, qos: qos)
    }

    func validatedData(for request: URLRequest, server: CalibreServer, timeout: Double = 600, qos: DispatchQoS.QoSClass = .default) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await urlSession(server: server, timeout: timeout, qos: qos).data(for: request)
            let httpResponse = try validateHTTPResponse(data: data, response: response)
            return (data, httpResponse)
        } catch {
            throw CalibreAPIError(error: error)
        }
    }

    func validatedDataPublisher(from url: URL, server: CalibreServer, timeout: Double = 600, qos: DispatchQoS.QoSClass = .default) -> AnyPublisher<(Data, HTTPURLResponse), CalibreAPIError> {
        validatedDataPublisher(for: URLRequest(url: url), server: server, timeout: timeout, qos: qos)
    }

    func validatedDataPublisher(for request: URLRequest, server: CalibreServer, timeout: Double = 600, qos: DispatchQoS.QoSClass = .default) -> AnyPublisher<(Data, HTTPURLResponse), CalibreAPIError> {
        Deferred {
            Future { promise in
                Task {
                    do {
                        promise(.success(try await self.validatedData(for: request, server: server, timeout: timeout, qos: qos)))
                    } catch {
                        promise(.failure(CalibreAPIError(error: error)))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func validateHTTPResponse(data: Data, response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalibreAPIError.unsupportedPayload
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            return httpResponse
        case 401, 403:
            throw CalibreAPIError.authFailed
        default:
            throw CalibreAPIError.httpStatus(httpResponse.statusCode, data)
        }
    }

    func decodePayload<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CalibreAPIError.decoding(error)
        }
    }
}

struct CalibreServerURLSessionKey: Hashable, Equatable {
    let server: CalibreServer
    let timeout: Double
    let qos: DispatchQoS.QoSClass
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(server)
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
    var url: URL
    var reachable: Bool = false
    var probing: Bool = false
    var errorMsg: String = "Waiting to connect"
    var defaultLibrary: String
    var libraryMap: [String:String] = [:]
    
    var error: CalibreAPIError? = nil

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
