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
