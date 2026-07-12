import Foundation

struct AdvancedQAStatus: Codable, Hashable {
    var enabled: Bool
    var state: String
    var retrievalScopes: AdvancedQARetrievalScopes? = nil
    var libraries: [AdvancedQALibraryStatus] = []

    enum CodingKeys: String, CodingKey {
        case enabled, state, libraries
        case retrievalScopes = "retrieval_scopes"
    }

    init(enabled: Bool, state: String, retrievalScopes: AdvancedQARetrievalScopes? = nil,
         libraries: [AdvancedQALibraryStatus] = []) {
        self.enabled = enabled
        self.state = state
        self.retrievalScopes = retrievalScopes
        self.libraries = libraries
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        state = try values.decode(String.self, forKey: .state)
        retrievalScopes = try values.decodeIfPresent(AdvancedQARetrievalScopes.self, forKey: .retrievalScopes)
        libraries = try values.decodeIfPresent([AdvancedQALibraryStatus].self, forKey: .libraries) ?? []
    }

    var isReady: Bool { enabled && state == "ready" }
}

struct AdvancedQASyncSummary: Codable, Hashable {
    var jobId: Int?
    var status: String?
    var totalBooks: Int?
    var processedBooks: Int?
    var indexedBooks: Int?
    var errorCount: Int?
    var queuedAt: String?
    var startedAt: String?
    var completedAt: String?
    var lastSyncAt: String?
    var errorMessage: String?
    var aborted: Bool?

    enum CodingKeys: String, CodingKey {
        case status, aborted
        case jobId = "job_id"
        case totalBooks = "total_books"
        case processedBooks = "processed_books"
        case indexedBooks = "indexed_books"
        case errorCount = "error_count"
        case queuedAt = "queued_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case lastSyncAt = "last_sync_at"
        case errorMessage = "error_message"
    }
}

struct AdvancedQALibraryStatus: Codable, Hashable, Identifiable {
    var libraryId: String
    var libraryUUID: String? = nil
    var displayName: String? = nil
    var kbSlug: String? = nil
    var mappingEnabled: Bool? = nil
    var sync: AdvancedQASyncSummary? = nil

    var id: String { libraryId }

    enum CodingKeys: String, CodingKey {
        case sync
        case libraryId = "library_id"
        case libraryUUID = "library_uuid"
        case displayName = "display_name"
        case kbSlug = "kb_slug"
        case mappingEnabled = "mapping_enabled"
    }
}

struct AdvancedQASyncJob: Codable, Hashable, Identifiable {
    var libraryId: String
    var libraryUUID: String?
    var displayName: String?
    var kbSlug: String?
    var mappingEnabled: Bool?
    var jobId: Int?
    var status: String?
    var totalBooks: Int?
    var processedBooks: Int?
    var indexedBooks: Int?
    var errorCount: Int?
    var queuedAt: String?
    var startedAt: String?
    var completedAt: String?
    var lastSyncAt: String?
    var errorMessage: String?
    var aborted: Bool?

    var id: String { jobId.map(String.init) ?? "\(libraryId):\(queuedAt ?? status ?? "unknown")" }

    enum CodingKeys: String, CodingKey {
        case status, aborted
        case libraryId = "library_id"
        case libraryUUID = "library_uuid"
        case displayName = "display_name"
        case kbSlug = "kb_slug"
        case mappingEnabled = "mapping_enabled"
        case jobId = "job_id"
        case totalBooks = "total_books"
        case processedBooks = "processed_books"
        case indexedBooks = "indexed_books"
        case errorCount = "error_count"
        case queuedAt = "queued_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case lastSyncAt = "last_sync_at"
        case errorMessage = "error_message"
    }
}

struct AdvancedQAPagination: Codable, Hashable {
    var page: Int
    var pageSize: Int
    var total: Int
    var hasNext: Bool

    enum CodingKeys: String, CodingKey {
        case page, total
        case pageSize = "page_size"
        case hasNext = "has_next"
    }
}

struct AdvancedQASyncJobsPage: Codable, Hashable {
    var items: [AdvancedQASyncJob]
    var pagination: AdvancedQAPagination
}

struct AdvancedQASyncJobBook: Codable, Hashable, Identifiable {
    var bookId: Int
    var format: String?
    var externalId: String?
    var status: String
    var error: String?

    var id: String { "\(bookId):\(format ?? ""):\(externalId ?? "")" }

    enum CodingKeys: String, CodingKey {
        case format, status, error
        case bookId = "book_id"
        case externalId = "external_id"
    }
}

struct AdvancedQASyncJobDetailPage: Codable, Hashable {
    var job: AdvancedQASyncJob
    var books: [AdvancedQASyncJobBook]
    var pagination: AdvancedQAPagination
}

struct AdvancedQARetrievalScopes: Codable, Hashable {
    var version: Int
    var defaultKind: String
    var items: [AdvancedQARetrievalScopeCapability]
    var isLegacy = false

    enum CodingKeys: String, CodingKey {
        case version, items
        case defaultKind = "default"
    }

    static func legacy(hasPosition: Bool) -> Self {
        let read = AdvancedQARetrievalScopeCapability(
            kind: "current_book_read",
            labelKey: "advanced_qa.scope.current_book_read.label",
            descriptionKey: "advanced_qa.scope.current_book_read.description",
            fallbackLabel: "Current book (read portion)",
            fallbackDescription: "Search this book only up to the current reading position.",
            spoilerSafe: true,
            spoilerRisk: "read_boundary",
            requires: ["position"],
            parameters: []
        )
        let wholeBook = AdvancedQARetrievalScopeCapability(
            kind: "current_book",
            labelKey: "advanced_qa.scope.current_book.label",
            descriptionKey: "advanced_qa.scope.current_book.description",
            fallbackLabel: "Current book",
            fallbackDescription: "Search the entire current book, including unread sections.",
            spoilerSafe: false,
            spoilerRisk: "full_text",
            requires: [],
            parameters: []
        )
        return Self(version: 0, defaultKind: hasPosition ? read.kind : wholeBook.kind,
                    items: [read, wholeBook], isLegacy: true)
    }
}

struct AdvancedQARetrievalScopeCapability: Codable, Hashable, Identifiable {
    var kind: String
    var labelKey: String
    var descriptionKey: String
    var fallbackLabel: String
    var fallbackDescription: String
    var spoilerSafe: Bool
    var spoilerRisk: String
    var requires: [String]
    var parameters: [String]

    var id: String { kind }

    enum CodingKeys: String, CodingKey {
        case kind, requires, parameters
        case labelKey = "label_key"
        case descriptionKey = "description_key"
        case fallbackLabel = "fallback_label"
        case fallbackDescription = "fallback_description"
        case spoilerSafe = "spoiler_safe"
        case spoilerRisk = "spoiler_risk"
    }

    var localizedLabel: String {
        NSLocalizedString(labelKey, tableName: nil, bundle: .main, value: fallbackLabel, comment: "Advanced QA scope")
    }

    var localizedDescription: String {
        NSLocalizedString(descriptionKey, tableName: nil, bundle: .main, value: fallbackDescription, comment: "Advanced QA scope description")
    }

    var spoilerDescription: String {
        switch spoilerRisk {
        case "strict": return "Only the current chapter or page is used."
        case "read_boundary": return "Content after your current reading position is excluded."
        case "client_controlled": return "Only context supplied by the reader is used."
        case "highest": return "Highest spoiler risk: searches all accessible indexed books."
        case "full_text": return "May include unread content."
        default: return spoilerSafe ? "Designed to reduce spoilers." : "May include spoilers."
        }
    }
}

struct AdvancedQARetrievalScopeSelection: Codable, Hashable {
    struct Relation: Codable, Hashable, Identifiable {
        var kind: String
        var id: String { kind }
    }

    struct BookReference: Codable, Hashable, Identifiable {
        var libraryId: String
        var bookId: Int
        var format: String?
        var id: String { "\(libraryId):\(bookId):\(format ?? "")" }

        enum CodingKeys: String, CodingKey {
            case format
            case libraryId = "library_id"
            case bookId = "book_id"
        }
    }

    var kind: String
    var relations: [Relation] = []
    var combine: String? = nil
    var includeCurrentBook: Bool? = nil
    var books: [BookReference] = []
    var bookIds: [Int] = []

    enum CodingKeys: String, CodingKey {
        case kind, relations, combine, books
        case includeCurrentBook = "include_current_book"
        case bookIds = "book_ids"
    }
}

enum AdvancedQAAvailability: String, Codable, Hashable {
    case unknown
    case ready
    case disabled
    case unavailable
    case unsupported

    init(status: AdvancedQAStatus) {
        if status.enabled == false { self = .disabled }
        else if status.state == "ready" { self = .ready }
        else { self = .unavailable }
    }

    var title: String {
        switch self {
        case .unknown: return "Not checked"
        case .ready: return "Ready"
        case .disabled: return "Disabled"
        case .unavailable: return "Unavailable"
        case .unsupported: return "Unsupported"
        }
    }

    var detail: String? {
        switch self {
        case .unsupported: return "Update DSReaderHelper"
        case .unavailable: return "Cortex unavailable"
        default: return nil
        }
    }
}

struct AdvancedQAStatusDetection: Hashable {
    var status: AdvancedQAStatus?
    var availability: AdvancedQAAvailability
}

enum AdvancedQAMode: String, Codable, CaseIterable, Hashable {
    case explain
    case translate
    case define
    case ask
}

struct ReaderSelectionContext: Codable, Hashable {
    struct Book: Codable, Hashable {
        var id: String
        var libraryId: String?
        var title: String
        var authors: [String]
        var format: String
        var series: String? = nil

        enum CodingKeys: String, CodingKey {
            case id, title, authors, format, series
            case libraryId = "library_id"
        }
    }

    struct Selection: Codable, Hashable {
        var text: String
        var normalizedText: String?
        var language: String?

        enum CodingKeys: String, CodingKey {
            case text, language
            case normalizedText = "normalized_text"
        }
    }

    struct Location: Codable, Hashable {
        var engine: String
        var chapter: String?
        var tocPath: [String]
        var page: Int?
        var href: String?
        var fragmentId: String?
        var cfi: String?
        var cfiStart: String?
        var cfiEnd: String?
        var progress: Double?

        enum CodingKeys: String, CodingKey {
            case engine, chapter, page, href, cfi, progress
            case tocPath = "toc_path"
            case fragmentId = "fragment_id"
            case cfiStart = "cfi_start"
            case cfiEnd = "cfi_end"
        }
    }

    struct SurroundingText: Codable, Hashable {
        var before: String
        var after: String
        var visible: String?

        enum CodingKeys: String, CodingKey {
            case before, after, visible
        }
    }

    var book: Book
    var selection: Selection
    var location: Location
    var surroundingText: SurroundingText

    enum CodingKeys: String, CodingKey {
        case book, selection, location
        case surroundingText = "surrounding_text"
    }
}

struct ReferenceCandidate: Codable, Hashable, Identifiable {
    var id: String
    var source: String
    var bookId: String
    var title: String
    var snippet: String
    var location: ReaderSelectionContext.Location
    var score: Double

    enum CodingKeys: String, CodingKey {
        case id, source, title, snippet, location, score
        case bookId = "book_id"
    }
}

struct Evidence: Codable, Hashable, Identifiable {
    var id: String
    var source: String
    var title: String
    var content: String
    var location: ReaderSelectionContext.Location?
    var metadata: [String: JSONValue]
}

enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let decoded = try? value.decode(Bool.self) { self = .bool(decoded) }
        else if let decoded = try? value.decode(Double.self) { self = .number(decoded) }
        else if let decoded = try? value.decode(String.self) { self = .string(decoded) }
        else if let decoded = try? value.decode([String: JSONValue].self) { self = .object(decoded) }
        else { self = .array(try value.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let decoded): try value.encode(decoded)
        case .number(let decoded): try value.encode(decoded)
        case .bool(let decoded): try value.encode(decoded)
        case .object(let decoded): try value.encode(decoded)
        case .array(let decoded): try value.encode(decoded)
        case .null: try value.encodeNil()
        }
    }
}

struct AdvancedQAOptions: Codable, Hashable {
    var useDictionary = true
    var useReference = true
    var useRag = true
    var maxEvidence = 8

    enum CodingKeys: String, CodingKey {
        case useDictionary = "use_dictionary"
        case useReference = "use_reference"
        case useRag = "use_rag"
        case maxEvidence = "max_evidence"
    }
}

struct AdvancedQARequest: Codable, Hashable {
    var qaApiVersion = 2
    var query: String
    var mode: AdvancedQAMode
    var responseLanguage: String = Locale.preferredLanguages.first ?? "en"
    var readerContext: ReaderSelectionContext
    var referenceCandidates: [ReferenceCandidate]
    var retrievalScope = AdvancedQARetrievalScopeSelection(kind: "current_book_read")
    var options = AdvancedQAOptions()

    enum CodingKeys: String, CodingKey {
        case query, mode, options
        case responseLanguage = "response_language"
        case qaApiVersion = "qa_api_version"
        case readerContext = "reader_context"
        case referenceCandidates = "reference_candidates"
        case retrievalScope = "retrieval_scope"
    }
}

struct QAAnswer: Codable, Hashable {
    var text: String
    var citations: [String]
}

struct QACard: Codable, Hashable, Identifiable {
    var type: String
    var title: String
    var html: String?
    var plainText: String?
    var id: String { "\(type):\(title)" }

    enum CodingKeys: String, CodingKey {
        case type, title, html
        case plainText = "plain_text"
    }
}

struct QAAction: Codable, Hashable, Identifiable {
    var type: String
    var title: String
    var location: ReaderSelectionContext.Location
    var id: String { "\(type):\(title)" }
}

struct AdvancedQAResponse: Codable, Hashable {
    var qaApiVersion: Int
    var answer: QAAnswer
    var cards: [QACard]
    var evidence: [Evidence]
    var actions: [QAAction]
    var warnings: [String]

    enum CodingKeys: String, CodingKey {
        case answer, cards, evidence, actions, warnings
        case qaApiVersion = "qa_api_version"
    }
}
