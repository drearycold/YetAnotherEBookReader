//
//  CalibreServerService+Discovery.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation

extension CalibreServerService {
    func getProtectionSpace(server: CalibreServer, port: Int?) -> URLProtectionSpace? {
        guard server.username.count > 0 && server.password.count > 0,
              let url = getServerUrlByReachability(server: server),
              let host = url.host else {
            return nil
        }

        var authMethod = NSURLAuthenticationMethodDefault
        if url.scheme == "http" {
            authMethod = NSURLAuthenticationMethodHTTPDigest
        }
        if url.scheme == "https" {
            authMethod = NSURLAuthenticationMethodHTTPBasic
        }
        return URLProtectionSpace(
            host: host,
            port: port ?? url.port ?? 0,
            protocol: url.scheme,
            realm: "calibre",
            authenticationMethod: authMethod
        )
    }

    func getServerUrlByReachability(server: CalibreServer) -> URL? {
        let serverInfos = calibreServerInfoStaging
            .filter { $1.reachable && $1.server.id == server.id }
            .sorted { !$0.value.isPublic && $1.value.isPublic }
        guard let serverInfo = serverInfos.first else {
            return nil
        }
        return serverInfo.value.isPublic ? URL(string: server.publicUrl) : URL(string: server.baseUrl)
    }

    func probeServerReachability(serverInfo: CalibreServerInfo) async -> CalibreServerInfo {
        var resultInfo = serverInfo
        resultInfo.reachable = false
        resultInfo.errorMsg = "Cannot connect"
        resultInfo.error = nil
        resultInfo.httpStatusCode = nil
        resultInfo.libraryMap = [:]

        var url = resultInfo.url
        url.appendPathComponent("/ajax/library-info", isDirectory: false)

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        return await withActivity(.probe, request: request, resultError: { $0.error }) { activity in
            do {
                let (data, response) = try await validatedData(for: request, server: serverInfo.server, timeout: 10, activity: activity)
                resultInfo.httpStatusCode = response.statusCode
                try requireJSON(response)
                let libraryInfo = try decodePayload(CalibreServerLibraryInfo.self, from: data)
                guard let defaultLibrary = libraryInfo.defaultLibrary,
                      libraryInfo.libraryMap.count > 0 else {
                    resultInfo.errorMsg = "Server has no library"
                    resultInfo.error = .unsupportedPayload
                    return resultInfo
                }

                resultInfo.defaultLibrary = defaultLibrary
                resultInfo.libraryMap = libraryInfo.libraryMap
                resultInfo.errorMsg = "Success"
                resultInfo.error = nil
                resultInfo.reachable = true
                return resultInfo
            } catch {
                let apiError = CalibreAPIError(error: error)
                resultInfo.httpStatusCode = resultInfo.httpStatusCode ?? activity.httpStatusCode
                resultInfo.error = apiError
                if case .transport(let transportError) = apiError, transportError.code == .cancelled {
                    resultInfo.errorMsg = "cancelled, server may require authentication"
                } else {
                    resultInfo.errorMsg = apiError.localizedDescription
                }
                return resultInfo
            }
        }
    }

    func probeLibrary(library: CalibreLibrary, serverURL: URL? = nil) async -> CalibreLibraryProbeTask {
        guard let task = buildProbeLibraryTask(library: library, serverURL: serverURL) else {
            return CalibreLibraryProbeTask(library: library, probeUrl: .init(fileURLWithPath: "/realm"), probeResult: nil)
        }

        do {
            return try await withRequestActivity(
                .probe, request: URLRequest(url: task.probeUrl), server: task.library.server, libraryId: task.library.id
            ) { data, response in
                try requireJSON(response)
                var result = task
                result.probeResult = try decodePayload(CalibreLibraryBooksResult.SearchResult.self, from: data)
                return result
            }
        } catch {
            return task
        }
    }

    func buildProbeLibraryTask(library: CalibreLibrary, serverURL: URL? = nil) -> CalibreLibraryProbeTask? {
        guard let serverURL = serverURL ?? getServerUrlByReachability(server: library.server) else { return nil }
        guard let probeUrl = try? makeEndpointURL(
            serverURL: serverURL,
            path: "/ajax/search/\(library.key)",
            queryItems: [URLQueryItem(name: "num", value: "0")]
        ) else {
            return nil
        }

        return .init(
            library: library,
            probeUrl: probeUrl
        )
    }
}

/// Keep an HTTP authentication challenge's status when URLSession cancels after rejection.
/// This delegate is per request and follows the shared delegate's credential/retry policy.
class CalibreServerDiagnosticTaskDelegate: CalibreServerTaskDelegate {
    private let lock = NSLock()
    private var statusCode: Int?

    var authenticationStatusCode: Int? {
        lock.lock()
        defer { lock.unlock() }
        return statusCode
    }

    override func urlSession(_ session: URLSession, task: URLSessionTask,
                             didReceive challenge: URLAuthenticationChallenge,
                             completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let response = challenge.failureResponse as? HTTPURLResponse {
            lock.lock()
            statusCode = response.statusCode
            lock.unlock()
        }
        super.urlSession(session, task: task, didReceive: challenge, completionHandler: completionHandler)
    }
}
