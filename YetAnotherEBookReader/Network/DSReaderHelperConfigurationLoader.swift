import Foundation

struct DSReaderHelperConfigurationRequest {
    struct Library: Equatable {
        let id: String
        let key: String
        let name: String
        let hidden: Bool
    }

    let server: CalibreServer
    let baseURL: URL
    let port: Int
    let libraries: [Library]
    let stored: DSReaderHelperStoredConfiguration
}

struct DSReaderHelperConfigurationPayload {
    let configuration: CalibreDSReaderHelperConfiguration
    let data: Data

    // One source of truth for a response, including any fields the client doesn't use.
    init(data: Data, service: CalibreServerService) throws {
        configuration = try service.decodePayload(CalibreDSReaderHelperConfiguration.self, from: data)
        self.data = data
    }

    init(configuration: CalibreDSReaderHelperConfiguration) throws {
        self.data = try JSONEncoder().encode(configuration)
        self.configuration = configuration
    }
}

enum DSReaderHelperConfigurationLoader {
    static func load(
        service: CalibreServerService,
        request: DSReaderHelperConfigurationRequest
    ) async throws -> DSReaderHelperConfigurationPayload {
        let connector = DSReaderHelperConnector(
            calibreServerService: service, server: request.server,
            dsreaderHelperServer: .init(port: request.port), goodreadsSync: nil
        )
        let global: DSReaderHelperConfigurationPayload
        do {
            global = try await connector.fetchConfiguration(baseURL: request.baseURL)
        } catch CalibreAPIError.httpStatus(404, let body) where body?.isEmpty == true {
            // Calibre's router returns an empty 404 for an unregistered route.
            // This is the only compatibility probe; the legacy response must validate too.
            try Task.checkCancellation()
            return try await connector.fetchConfiguration(baseURL: request.baseURL, legacy: true)
        }

        guard global.configuration.count_pages_prefs != nil else { return global }

        var configuration = global.configuration
        var libraryConfigs: [String: CalibreCountPagesPrefs.LibraryConfig] = [:]
        if let stored = request.stored.helper, stored.port == request.port,
           let previous = stored.configuration?.count_pages_prefs?.library_config {
            for library in request.libraries where library.hidden {
                libraryConfigs[library.name] = previous[library.name] ?? previous[library.key]
            }
        }

        // Limit each batch to four requests, even for servers with many libraries.
        for batch in request.libraries.filter({ !$0.hidden }).chunks(size: 4) {
            try Task.checkCancellation()
            try await withThrowingTaskGroup(of: (String, CalibreCountPagesPrefs.LibraryConfig).self) { group in
                for library in batch {
                    group.addTask {
                        let columns = try await connector.fetchLibraryConfiguration(baseURL: request.baseURL, library: library)
                        return (library.name, columns)
                    }
                }
                for try await (name, columns) in group {
                    libraryConfigs[name] = columns
                }
            }
        }
        try Task.checkCancellation()
        configuration.count_pages_prefs?.library_config = libraryConfigs
        return try DSReaderHelperConfigurationPayload(configuration: configuration)
    }
}
