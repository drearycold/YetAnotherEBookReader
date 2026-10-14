//
//  CalibreServerService.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/12.
//

import Foundation
import OSLog

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
    /// Requests running in each session (`withURLSession`). Creating a task in an invalidated
    /// session raises, so a retired session is invalidated only after its last request.
    private var sessionLeases = [ObjectIdentifier: Int]()
    /// Retired sessions that still have requests running.
    private var retiredSessions = [ObjectIdentifier: URLSession]()

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

    /// The cached session for `server`'s address, username and password. A server's sessions all
    /// use the newest password asked for: a session for another password is retired, and
    /// invalidated once its requests finish. Make requests through `withURLSession` (or
    /// `validatedData`), which keeps the session valid until the request is done.
    func urlSession(server: CalibreServer, timeout: Double = 600, qos: DispatchQoS.QoSClass = .default) -> URLSession {
        let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
        return sessionsQueue.sync { cachedSession(for: key) }
    }

    /// Runs `body` with the session for `server`, which stays valid until `body` returns even if a
    /// newer password retires it meanwhile.
    func withURLSession<T>(
        server: CalibreServer,
        timeout: Double = 600,
        qos: DispatchQoS.QoSClass = .default,
        _ body: (URLSession) async throws -> T
    ) async rethrows -> T {
        let key = CalibreServerURLSessionKey(server: server, timeout: timeout, qos: qos)
        let session = sessionsQueue.sync {
            let session = cachedSession(for: key)
            sessionLeases[ObjectIdentifier(session), default: 0] += 1
            return session
        }
        defer { endLease(of: session) }
        return try await body(session)
    }

    /// Retires every session for `server` (matched by address and username), for a removed server.
    func retireSessions(for server: CalibreServer) {
        sessionsQueue.sync {
            for key in metadataSessions.keys.filter({ $0.server == server }) {
                if let session = metadataSessions.removeValue(forKey: key) {
                    retire(session)
                }
            }
        }
    }

    /// On `sessionsQueue`.
    private func cachedSession(for key: CalibreServerURLSessionKey) -> URLSession {
        if let session = metadataSessions[key] {
            return session
        }
        let staleKeys = metadataSessions.keys.filter {
            $0.server == key.server && $0.server.password != key.server.password
        }
        for staleKey in staleKeys {
            if let session = metadataSessions.removeValue(forKey: staleKey) {
                retire(session)
            }
        }

        let urlSessionConfiguration = URLSessionConfiguration.default
        urlSessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        urlSessionConfiguration.timeoutIntervalForRequest = key.timeout
        urlSessionConfiguration.httpMaximumConnectionsPerHost = 4
        let urlSessionDelegate = CalibreServerTaskDelegate(key.server)
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: urlSessionDelegate, delegateQueue: metadataQueue)

        metadataSessions[key] = urlSession
        return urlSession
    }

    /// On `sessionsQueue`, after removing `session` from `metadataSessions`.
    private func retire(_ session: URLSession) {
        let id = ObjectIdentifier(session)
        // Tests cache one mock session under several keys.
        guard metadataSessions.values.contains(where: { $0 === session }) == false else { return }
        if sessionLeases[id] != nil {
            retiredSessions[id] = session
        } else {
            session.finishTasksAndInvalidate()
        }
    }

    private func endLease(of session: URLSession) {
        sessionsQueue.sync {
            let id = ObjectIdentifier(session)
            let leases = (sessionLeases[id] ?? 1) - 1
            sessionLeases[id] = leases > 0 ? leases : nil
            if leases <= 0, let retired = retiredSessions.removeValue(forKey: id) {
                retired.finishTasksAndInvalidate()
            }
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
            let (data, response) = try await withURLSession(server: server, timeout: timeout, qos: qos) {
                try await $0.data(for: request)
            }
            let httpResponse = try validateHTTPResponse(data: data, response: response)
            return (data, httpResponse)
        } catch {
            throw CalibreAPIError(error: error)
        }
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

/// A session's task delegate answers authentication challenges with the password the session was
/// created with, so the key includes the password. `CalibreServer`'s own equality leaves it out.
struct CalibreServerURLSessionKey: Hashable {
    let server: CalibreServer
    let timeout: Double
    let qos: DispatchQoS.QoSClass

    static func == (lhs: CalibreServerURLSessionKey, rhs: CalibreServerURLSessionKey) -> Bool {
        lhs.server == rhs.server
            && lhs.server.password == rhs.server.password
            && lhs.timeout == rhs.timeout
            && lhs.qos == rhs.qos
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(server)
        hasher.combine(server.password)
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

/// Calibre keys a highlight by its `uuid`: 16 random bytes in base64url without padding, 22
/// characters (`short_uuid()` in calibre's viewer). The app keeps the same 16 bytes as a UUID
/// string. Calibre merges highlights by exact `uuid`, so the output must stay byte-for-byte the same.
func uuidFolioToCalibre(_ identifier: String) -> String? {
    guard let uuid = UUID(uuidString: identifier)?.uuid else {
        return nil
    }
    let data = withUnsafeBytes(of: uuid) { Data($0) }
    return base64ToBase64URL(base64: data.base64EncodedString())
}

func uuidCalibreToFolio(_ shortenedIdentifier: String?) -> String? {
    guard let shortenedIdentifier = shortenedIdentifier,
          let data = Data(base64Encoded: base64urlToBase64(base64url: shortenedIdentifier)),
          data.count == MemoryLayout<uuid_t>.size
    else { return nil }

    var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    withUnsafeMutableBytes(of: &uuid) { $0.copyBytes(from: data) }
    return UUID(uuid: uuid).uuidString
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
