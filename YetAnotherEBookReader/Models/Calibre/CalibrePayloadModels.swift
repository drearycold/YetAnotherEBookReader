//
//  CalibrePayloadModels.swift
//  YetAnotherEBookReader
//
//  Split from CalibreData.swift on 2026/6/18.
//  Zero-behavior-change move: Codable API response/entry payloads.
//

import Foundation

struct CalibreBookLastReadPositionEntry: Codable {
    let device: String
    let cfi: String
    let epoch: Double
    let pos_frac: Double
}

struct CalibreBookFormatMetadataEntry: Codable {
    var path: String?
    var size: UInt64 = 0
    var mtime: String = ""
    
    enum CodingKeys: String, CodingKey {
        case path
        case size
        case mtime
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        size = try container.decodeIfPresent(UInt64.self, forKey: .size) ?? 0
        mtime = try container.decodeIfPresent(String.self, forKey: .mtime) ?? ""
    }
    
    init(path: String? = nil, size: UInt64 = 0, mtime: String = "") {
        self.path = path
        self.size = size
        self.mtime = mtime
    }
}

struct CalibreBookUserMetadataEntry: Codable {
    var table: String = ""
    var column: String = ""
    var datatype: String = ""
    var is_multiple: Bool? = nil
    var kind: String = ""
    var name: String = ""
    var search_terms: [String] = []
    var label: String = ""
    var colnum: Int = 0
    var display: [String: String?] = [:]
    var is_custom: Bool = false
    var is_category: Bool = false
    var link_column: String = ""
    var category_sort: String = ""
    var is_csp: Bool = false
    var is_editable: Bool = false
    var rec_index: Int = 0
    var value: Any? = nil   //dynamic
    var extra: Any? = nil   //dynamic
    //var is_multiple2: ???
    
    enum CodingKeys: String, CodingKey {
        case table
    }
}

struct CalibreBookEntry: Codable {
//    var author_link_map: [String: String] = [:]   //removed as of calibre 6.18
    var user_metadata: [String: CalibreBookUserMetadataEntry] = [:]
    var tags: [String] = []
    var author_sort: String = ""
    var comments: String? = nil
    var title_sort: String = ""
    var thumbnail: String = ""
    var timestamp: String = ""
    var uuid: String = ""
    var user_categories: [String: String] = [:]
    var cover: String = ""
    var title: String = ""
    var last_modified: String = ""
    var application_id: Int = 0
    var series_index: Double? = nil
    var author_sort_map: [String: String] = [:]
    var identifiers: [String: String] = [:]
    var languages: [String] = []
    var publisher: String? = nil
    var series: String? = nil
    var pubdate: String = ""
    var rating: Double = 0.0
    var authors: [String] = []
    var format_metadata: [String: CalibreBookFormatMetadataEntry] = [:]
    var formats: [String] = []
    var main_format: [String: String]? = [:]
    var other_formats: [String: String]? = [:]
    var category_urls: [String: [String: String]] = [:]
}

struct CalibreBookMetadataFormatValue {
    var serverSize: UInt64
    var serverMTime: Date
}

struct CalibreBookMetadataValue {
    var title: String
    var publisher: String
    var series: String
    var seriesIndex: Double
    var pubDate: Date
    var timestamp: Date?
    var lastModified: Date?
    var authors: [String]
    var tags: [String]
    var formats: [String: CalibreBookMetadataFormatValue]
    var size: Int
    var rating: Int
    var identifiers: [String: String]
    var comments: String
    var userMetadatas: [String: Any]

    init(entry: CalibreBookEntry, root: NSDictionary) {
        let parserOne = ISO8601DateFormatter()
        parserOne.formatOptions = .withInternetDateTime
        let parserTwo = ISO8601DateFormatter()
        parserTwo.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        title = entry.title
        publisher = entry.publisher ?? ""
        series = entry.series ?? ""
        seriesIndex = entry.series_index ?? 0.0
        pubDate = parserTwo.date(from: entry.pubdate) ?? parserOne.date(from: entry.pubdate) ?? .distantPast
        timestamp = parserTwo.date(from: entry.timestamp) ?? parserOne.date(from: entry.timestamp)
        lastModified = parserTwo.date(from: entry.last_modified) ?? parserOne.date(from: entry.last_modified)
        authors = entry.authors
        tags = entry.tags
        formats = entry.format_metadata.reduce(into: [:]) { partialResult, formatEntry in
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
            partialResult[formatEntry.key.uppercased()] = CalibreBookMetadataFormatValue(
                serverSize: formatEntry.value.size,
                serverMTime: dateFormatter.date(from: formatEntry.value.mtime) ?? .distantPast
            )
        }
        size = 0
        rating = Int(entry.rating * 2)
        identifiers = entry.identifiers
        comments = entry.comments ?? ""

        userMetadatas = [:]
        if let userMetadata = root["user_metadata"] as? NSDictionary {
            userMetadatas = userMetadata.reduce(into: [:]) {
                guard let dict = $1.value as? NSDictionary,
                      let label = dict["label"] as? String,
                      let value = dict["#value#"] else {
                    return
                }
                $0[label] = value
            }
        }
    }

    func mergedFormats(with existing: [String: FormatInfo]) -> [String: FormatInfo] {
        formats.reduce(into: existing) { partialResult, formatEntry in
            var formatInfo = partialResult[formatEntry.key] ?? FormatInfo(
                serverSize: 0,
                serverMTime: .distantPast,
                cached: false,
                cacheSize: 0,
                cacheMTime: .distantPast
            )
            formatInfo.serverSize = formatEntry.value.serverSize
            formatInfo.serverMTime = formatEntry.value.serverMTime
            partialResult[formatEntry.key] = formatInfo
        }
    }

    func mergedUserMetadatas(with existing: [String: Any?]) -> [String: Any?] {
        userMetadatas.reduce(into: existing) { partialResult, entry in
            partialResult[entry.key] = entry.value
        }
    }

    func mergedUserMetadatas(with existing: [String: Any]) -> [String: Any] {
        userMetadatas.reduce(into: existing) { partialResult, entry in
            partialResult[entry.key] = entry.value
        }
    }
}

extension CalibreBook {
    mutating func applyMetadataValue(_ metadata: CalibreBookMetadataValue) {
        title = metadata.title
        publisher = metadata.publisher
        series = metadata.series
        seriesIndex = metadata.seriesIndex
        pubDate = metadata.pubDate
        timestamp = metadata.timestamp ?? .init()
        lastModified = metadata.lastModified ?? .init()
        lastSynced = lastModified
        tags = metadata.tags
        formats = metadata.mergedFormats(with: formats)
        size = metadata.size
        rating = metadata.rating
        authors = metadata.authors
        identifiers = metadata.identifiers
        comments = metadata.comments
        userMetadatas = metadata.mergedUserMetadatas(with: userMetadatas)
    }
}

struct CalibreBookAnnotationHighlightEntry: Codable {
    var type: String
    var timestamp: String
    var uuid: String

    var removed: Bool?

    var ranges: String?     //for PDF
    var startCfi: String?
    var endCfi: String?
    var highlightedText: String?
    var style:[String:String]?

    var spineName: String?
    var spineIndex: Int?
    var tocFamilyTitles: [String]?
    
    var notes: String?
    
    enum CodingKeys: String, CodingKey {
        case uuid
        case type
        
        case startCfi = "start_cfi"
        case endCfi = "end_cfi"
        case highlightedText = "highlighted_text"
        case style
        case timestamp

        case spineName = "spine_name"
        case spineIndex = "spine_index"
        case tocFamilyTitles = "toc_family_titles"
        
        case notes
        case ranges
        
        case removed
    }
}

struct CalibreBookAnnotationBookmarkEntry: Codable {
    var type: String
    var timestamp: String

    var pos_type: String
    var pos: String
    
    var title: String
    
    var removed: Bool?
    
    enum CodingKeys: String, CodingKey {
        case type
        case timestamp

        case pos_type
        case pos
        
        case title
        case removed
    }
}

struct CalibreBookAnnotationsResult: Codable {
    var last_read_positions: [CalibreBookLastReadPositionEntry]
    var annotations_map: CalibreBookAnnotationsMap
}

struct CalibreBookAnnotationsMap: Codable {
    var bookmark: [CalibreBookAnnotationBookmarkEntry]?
    var highlight: [CalibreBookAnnotationHighlightEntry]?
}

struct CalibreLibraryBooksResult: Codable {
    struct SearchResult: Codable {
        var total_num: Int
        var sort_order: String
        var num_books_without_search: Int
        var offset: Int
        var num: Int
        var sort: String
        var base_url: String
        var query: String?
        var library_id: String
        var book_ids: [Int32]
        var vl: String
    }
    
    struct BookMetadata: Codable {
        var title: String
        var authors: [String]
    }
    
    var search_result: SearchResult
    var metadata: [String: BookMetadata]
}
