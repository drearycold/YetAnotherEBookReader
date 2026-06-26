//
//  CalibreServerService+Discovery.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation
import Combine

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

        var url = resultInfo.url
        url.appendPathComponent("/ajax/library-info", isDirectory: false)

        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
            let (data, _) = try await validatedData(for: request, server: resultInfo.server, timeout: 10)
            let libraryInfo = try decodePayload(CalibreServerLibraryInfo.self, from: data)
            guard let defaultLibrary = libraryInfo.defaultLibrary,
                  libraryInfo.libraryMap.count > 0 else {
                resultInfo.errorMsg = "Server has no library"
                return resultInfo
            }

            resultInfo.defaultLibrary = defaultLibrary
            resultInfo.libraryMap = libraryInfo.libraryMap
            resultInfo.errorMsg = "Success"
            resultInfo.reachable = true
            return resultInfo
        } catch let error as CalibreAPIError {
            if case .transport(let transportError) = error, transportError.code == .cancelled {
                resultInfo.errorMsg = "cancelled, server may require authentication"
            } else {
                resultInfo.errorMsg = error.localizedDescription
            }
            return resultInfo
        } catch {
            resultInfo.errorMsg = error.localizedDescription
            return resultInfo
        }
    }

    func probeLibrary(library: CalibreLibrary) async -> CalibreLibraryProbeTask {
        guard let task = buildProbeLibraryTask(library: library) else {
            return CalibreLibraryProbeTask(library: library, probeUrl: .init(fileURLWithPath: "/realm"), probeResult: nil)
        }

        do {
            let (data, _) = try await validatedData(from: task.probeUrl, server: task.library.server)
            var task = task
            task.probeResult = try? JSONDecoder().decode(CalibreLibraryBooksResult.SearchResult.self, from: data)
            return task
        } catch {
            return task
        }
    }

    func probeServerReachabilityNew(serverInfo: CalibreServerInfo) -> AnyPublisher<CalibreServerInfo, Never> {
        var resultInfo = serverInfo
        resultInfo.reachable = false
        resultInfo.errorMsg = "Cannot connect"
        resultInfo.error = nil

        var url = resultInfo.url
        url.appendPathComponent("/ajax/library-info", isDirectory: false)

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)

        return validatedDataPublisher(for: request, server: resultInfo.server, timeout: 10)
            .tryMap { data, _ in
                try self.decodePayload(CalibreServerLibraryInfo.self, from: data)
            }
            .mapError(CalibreAPIError.init(error:))
            .map { libraryInfo -> CalibreServerInfo in
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
            }
            .catch { error -> Just<CalibreServerInfo> in
                resultInfo.error = error
                if case .transport(let transportError) = error, transportError.code == .cancelled {
                    resultInfo.errorMsg = "cancelled, server may require authentication"
                } else {
                    resultInfo.errorMsg = error.localizedDescription
                }
                return Just(resultInfo)
            }
            .eraseToAnyPublisher()
    }

    func buildProbeLibraryTask(library: CalibreLibrary) -> CalibreLibraryProbeTask? {
        guard let serverUrl = self.librarySyncStatus[library.id]?.isError == true
            ? URL(fileURLWithPath: "/realm")
            : (
                getServerUrlByReachability(server: library.server) ?? (
                    (library.autoUpdate || library.server.isLocal)
                    ? URL(fileURLWithPath: "/realm")
                    : nil
                )
            ) else {
            return nil
        }

        var probeUrlComponents = URLComponents()
        probeUrlComponents.path = "ajax/search/\(library.key)"
        probeUrlComponents.queryItems = [URLQueryItem(name: "num", value: "0")]

        guard let probeUrl = probeUrlComponents.url(relativeTo: serverUrl) else {
            return nil
        }

        return .init(
            library: library,
            probeUrl: probeUrl
        )
    }
}
