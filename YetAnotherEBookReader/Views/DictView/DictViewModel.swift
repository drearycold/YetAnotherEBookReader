//
//  DIctViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/7/29.
//

import Foundation
import WebKit
import OSLog

@MainActor class DictViewModel: ObservableObject {

    var server: String?
    var word: String?

    var tabWebView: [WKWebView] = []

    @Published var hints: [(word: String, freq: Int)] = []
    @Published var hintError: Error?
    @Published var isLoadingHints: Bool = false

    private let logger = Logger(subsystem: "io.github.dsreader", category: "DictViewModel")

    func loadHints(for word: String) async {
        guard let server = server, !word.isEmpty else { return }

        isLoadingHints = true
        defer { isLoadingHints = false }
        hintError = nil

        do {
            guard var urlComponent = URLComponents(string: server.replacingOccurrences(of: "/lookup", with: "/hint")) else {
                throw URLError(.badURL)
            }
            urlComponent.queryItems = [
                .init(name: "word", value: word.lowercased())
            ]
            guard let url = urlComponent.url else {
                throw URLError(.badURL)
            }

            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.init(rawValue: httpResponse.statusCode))
            }

            let result = try JSONDecoder().decode([String: [String: Int]].self, from: data)
            guard let prefixed = result["prefixed"] else {
                self.hints = []
                return
            }

            self.hints = prefixed.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value) }
        } catch {
            logger.error("Dictionary hint fetch failed: \(error.localizedDescription)")
            self.hintError = error
            self.hints = []
        }
    }
}
