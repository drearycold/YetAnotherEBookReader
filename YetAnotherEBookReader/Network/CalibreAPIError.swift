//
//  CalibreAPIError.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/6/17.
//

import Foundation

enum CalibreAPIError: LocalizedError {
    case serverUnreachable
    case invalidURL(String?)
    case transport(URLError)
    case httpStatus(Int, Data?)
    case decoding(Error)
    case emptyResponse
    case authFailed
    case serverRejected(String?)
    case unsupportedPayload
    case unknown(Error)

    init(error: Error) {
        if let calibreError = error as? CalibreAPIError {
            self = calibreError
        } else if let urlError = error as? URLError {
            self = .transport(urlError)
        } else {
            self = .unknown(error)
        }
    }

    var errorDescription: String? {
        switch self {
        case .serverUnreachable:
            return "Server not Reachable"
        case .invalidURL(let path):
            return path.map { "Invalid URL: \($0)" } ?? "Invalid URL"
        case .transport(let error):
            return error.localizedDescription
        case .httpStatus(let statusCode, let data):
            if statusCode == 404 {
                return "Deleted"
            }
            if let message = Self.payloadMessage(from: data) {
                return message
            }
            return "HTTP \(statusCode)"
        case .decoding:
            return "Failed to Parse Calibre Server Response."
        case .emptyResponse:
            return "Empty Response"
        case .authFailed:
            return "Authentication Failed"
        case .serverRejected(let message):
            return message ?? "Server Rejected Request"
        case .unsupportedPayload:
            return "Unsupported Response"
        case .unknown(let error):
            return error.localizedDescription
        }
    }

    var asURLError: URLError {
        switch self {
        case .transport(let error):
            return error
        case .serverUnreachable, .invalidURL:
            return URLError(.badURL)
        case .authFailed:
            return URLError(.userAuthenticationRequired)
        case .emptyResponse:
            return URLError(.zeroByteResource)
        case .httpStatus(let statusCode, _):
            switch statusCode {
            case 401, 403:
                return URLError(.userAuthenticationRequired)
            case 404:
                return URLError(.fileDoesNotExist)
            default:
                return URLError(.badServerResponse)
            }
        case .decoding, .unsupportedPayload, .serverRejected, .unknown:
            return URLError(.cannotParseResponse)
        }
    }

    private static func payloadMessage(from data: Data?) -> String? {
        guard let data,
              data.isEmpty == false,
              let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              message.isEmpty == false else {
            return nil
        }
        return message
    }
}
