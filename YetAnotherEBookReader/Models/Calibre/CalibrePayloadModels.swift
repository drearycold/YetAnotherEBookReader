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
