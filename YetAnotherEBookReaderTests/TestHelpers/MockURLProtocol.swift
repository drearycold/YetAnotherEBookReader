//
//  MockURLProtocol.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-23.
//

import Foundation

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        print("[DEBUG_LOG] MockURLProtocol.canInit: \(request.url?.absoluteString ?? "nil")")
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        print("[DEBUG_LOG] MockURLProtocol.startLoading: \(request.url?.absoluteString ?? "nil")")
        guard let handler = MockURLProtocol.requestHandler else {
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension MockURLProtocol {
    /// The requests a mock server answered, and those it didn't, by path.
    final class RequestLog: @unchecked Sendable {
        private let lock = NSLock()
        private var answeredPaths = [String]()
        private var unexpectedPaths = [String]()

        var answered: [String] {
            lock.lock()
            defer { lock.unlock() }
            return answeredPaths
        }

        var unexpected: [String] {
            lock.lock()
            defer { lock.unlock() }
            return unexpectedPaths
        }

        fileprivate func record(_ path: String, answered: Bool) {
            lock.lock()
            defer { lock.unlock() }
            if answered {
                answeredPaths.append(path)
            } else {
                unexpectedPaths.append(path)
            }
        }
    }

    /// Answers a request whose path is exactly a key of `answers` with that JSON; any other gets a
    /// 404 and is logged as unexpected. (The full library sync's mocks matched
    /// `path.contains("list")`, which hid that calibre had no route for its requests.)
    @discardableResult
    static func answer(_ answers: [String: String]) -> RequestLog {
        let log = RequestLog()
        requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            guard let json = answers[url.path] else {
                log.record(url.path, answered: false)
                return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            log.record(url.path, answered: true)
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        return log
    }
}
