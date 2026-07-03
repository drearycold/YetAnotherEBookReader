//
//  CalibreSyncModels.swift
//  YetAnotherEBookReader
//
//  Split from CalibreData.swift on 2026/6/18.
//  Zero-behavior-change move: custom-column, category, probe/sync value types
//  and the cdb cmd list result.
//

import Foundation

struct CalibreCustomColumnInfo: Codable, Hashable {
    var label: String
    var name: String
    var datatype: String
    var editable: Bool
    
    var display: CalibreCustomColumnDisplayInfo
    
    var normalized: Bool
    var num: Int
    var isMultiple: Bool
    var multipleSeps: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case label
        case name
        case datatype
        case editable
        case display
        case normalized
        case num
        case isMultiple = "is_multiple"
        case multipleSeps = "multiple_seps"
    }
}

struct CalibreCustomColumnDisplayInfo: Codable, Hashable {
    var description: String
    
    //type text
    var isNames: Bool?
    
    //tyoe composite
    var compositeTemplate: String?
    var compositeSort: String?
    var useDecorations: Int?
    var makeCategory: Bool?
    var containsHtml: Bool?
    
    //type int, float
    var numberFormat: String?
    
    //type comments
    var headingPosition: String?
    var interpretAs: String?
    
    //type rating
    var allowHalfStars: Bool?
    
    enum CodingKeys: String, CodingKey {
        case description
        
        case isNames = "is_names"
        
        case compositeTemplate = "composite_template"
        case compositeSort = "composite_sort"
        case useDecorations = "use_decorations"
        case makeCategory = "make_category"
        case containsHtml = "contains_html"
        
        case numberFormat = "number_format"
        
        case headingPosition = "heading_position"
        case interpretAs = "interpret_as"
        
        case allowHalfStars = "allow_half_stars"
    }
}

struct CalibreLibraryCategoryKey: Hashable {
    let libraryId: String
    let categoryName: String
}

struct CalibreUnifiedCategoryKey: Hashable {
    let categoryName: String
    let search: String
}

struct CalibreLibraryCategoryValue {
    var category: CalibreLibraryCategory
    var reqId: Int
    var totalNumber: Int
    var items: [LibraryCategoryListResult.Item]
}

struct CalibreProbeServerRequest: Identifiable {
    var id: String {
        server.id + " " + isPublic.description
    }
    
    let server: CalibreServer
    let isPublic: Bool
    
    let updateLibrary: Bool
    let autoUpdateOnly: Bool
    let incremental: Bool
}

struct CalibreProbeLibraryRequest: Identifiable {
    var id: String {
        library.id
    }
    
    let library: CalibreLibrary
}

struct CalibreSyncLibraryRequest {
    let library: CalibreLibrary
    let autoUpdateOnly: Bool
    let incremental: Bool
}

struct CalibreSyncLibraryResult {
    let request: CalibreSyncLibraryRequest
    var isIncremental: Bool = true
    var result: [String: [String:CalibreCustomColumnInfo]]
    var errmsg = ""
    var categories: [CalibreLibraryCategory] = []
    var list = CalibreCdbCmdListResult()
    
    //parsed
    var isError = false
    var bookCount = 0
    var bookNeedUpdateCount = 0
    var bookDeleted = [Int32]()
    var lastModified: Date? = nil
}

struct BookMetadataSyncRecord {
    let id: Int32
    let lastModified: Date
}

struct BookMetadataPersistenceResult {
    var booksUpdated = Set<Int32>()
    var booksDeleted = Set<Int32>()
    var booksInShelf = [CalibreBook]()
    var booksAnnotation = [CalibreBook]()
}

struct CalibreSyncLibraryBooksMetadata {
    enum Action {
        case save([BookMetadataSyncRecord])
        case updateDeleted([String: CalibreCdbCmdListResult.DateValue])
        case complete(Date?, [String: CalibreCustomColumnInfo])
    }
    
    let library: CalibreLibrary
    let action: Action
    let preMsg: String
    let postMsg: String
    
    //parsed
    var bookCount = 0
    var bookNeedUpdateCount = 0
    var bookToUpdate = [Int32]()
    var bookDeleted = [Int32]()
}

struct CalibreLibraryCategory: Codable {
    var name: String
    var url: String
    var icon: String
    var is_category: Bool
}

struct CalibreCdbCmdListResult: Codable, Hashable {
    struct DateValue: Codable, Hashable {
        var v: String
    }
    struct Data: Codable, Hashable {
        var last_modified: [String: DateValue] = [:]
//        var title: [String: String] = [:]
//        var authors: [String: [String]] = [:]
//        var formats: [String: Set<String>] = [:]
//        var series: [String: String?] = [:]
//        var series_index: [String: Double] = [:]
//        var identifiers: [String: [String: String]] = [:]
//        var timestamp: [String: DateValue] = [:]
//        var pubdate: [String: DateValue] = [:]
    }
    
    var book_ids = [Int32]()
    var data = Data()
}
