//
//  CalibreSyncModels.swift
//  YetAnotherEBookReader
//
//  Split from CalibreData.swift on 2026/6/18.
//  Custom-column, category and probe/sync value types.
//

import Foundation

/// A custom column's definition, keyed by its label in `CalibreLibrary.customColumnInfos`.
/// `CalibreLibraryManager.syncLibrary` reads it from `ajax/books` (`init(userMetadata:)`); Realm keeps
/// it encoded with these keys, which are those of calibre's `cdb` interface that read it before.
struct CalibreCustomColumnInfo: Codable, Hashable {
    var label: String
    var name: String
    var datatype: String
    var editable: Bool
    
    var display: CalibreCustomColumnDisplayInfo
    
    var num: Int
    var isMultiple: Bool
    var multipleSeps: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case label
        case name
        case datatype
        case editable
        case display
        case num
        case isMultiple = "is_multiple"
        case multipleSeps = "multiple_seps"
    }
}

extension CalibreCustomColumnInfo {
    /// Only the label, name and type are required: a missing or unexpected value elsewhere takes its
    /// default rather than losing the column.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        name = try container.decode(String.self, forKey: .name)
        datatype = try container.decode(String.self, forKey: .datatype)
        editable = (try? container.decodeIfPresent(Bool.self, forKey: .editable)) ?? false
        display = (try? container.decodeIfPresent(CalibreCustomColumnDisplayInfo.self, forKey: .display)) ?? .init()
        num = (try? container.decodeIfPresent(Int.self, forKey: .num)) ?? 0
        isMultiple = (try? container.decodeIfPresent(Bool.self, forKey: .isMultiple)) ?? false
        multipleSeps = (try? container.decodeIfPresent([String: String].self, forKey: .multipleSeps)) ?? [:]
    }

    init(userMetadata column: CalibreBookUserMetadataColumn) {
        self.init(
            label: column.label,
            name: column.name,
            datatype: column.datatype,
            editable: column.isEditable,
            display: column.display,
            num: column.colnum,
            isMultiple: column.isMultiple,
            multipleSeps: column.multipleSeps
        )
    }
}

/// How calibre shows a column. calibre stores only what was set: a column made with
/// `calibredb add_custom_column` has `"display": {}`, so every field is optional, and one of an
/// unexpected type is dropped rather than failing the column.
struct CalibreCustomColumnDisplayInfo: Codable, Hashable {
    var description: String = ""
    
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

extension CalibreCustomColumnDisplayInfo {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? ""
        isNames = try? container.decodeIfPresent(Bool.self, forKey: .isNames)
        compositeTemplate = try? container.decodeIfPresent(String.self, forKey: .compositeTemplate)
        compositeSort = try? container.decodeIfPresent(String.self, forKey: .compositeSort)
        useDecorations = try? container.decodeIfPresent(Int.self, forKey: .useDecorations)
        makeCategory = try? container.decodeIfPresent(Bool.self, forKey: .makeCategory)
        containsHtml = try? container.decodeIfPresent(Bool.self, forKey: .containsHtml)
        numberFormat = try? container.decodeIfPresent(String.self, forKey: .numberFormat)
        headingPosition = try? container.decodeIfPresent(String.self, forKey: .headingPosition)
        interpretAs = try? container.decodeIfPresent(String.self, forKey: .interpretAs)
        allowHalfStars = try? container.decodeIfPresent(Bool.self, forKey: .allowHalfStars)
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
    
    /// Add the server's new libraries and sync each one (`CalibreLibraryManager.syncLibrary`).
    let updateLibrary: Bool
    /// An automatic probe: with `updateLibrary`, it doesn't also fetch the DSReader Helper
    /// configuration, as a probe the user asks for does.
    let autoUpdateOnly: Bool
}

struct CalibreProbeLibraryRequest: Identifiable {
    var id: String {
        library.id
    }
    
    let library: CalibreLibrary
}

struct CalibreSyncLibraryRequest {
    let library: CalibreLibrary
}

/// What `CalibreServerService.getLibrarySummary` reads about a library.
struct CalibreLibrarySummary: Equatable {
    /// The books the user may see.
    var bookCount: Int
    /// The newest change to any of them; nil for an empty library.
    var lastModified: Date? = nil
    /// The library's custom columns by label; nil for an empty library, which has no book to
    /// describe them.
    var customColumnInfos: [String: CalibreCustomColumnInfo]? = nil
}

struct BookMetadataPersistenceResult {
    var booksUpdated = Set<Int32>()
    var booksDeleted = Set<Int32>()
    var booksInShelf = [CalibreBook]()
    var booksAnnotation = [CalibreBook]()
}

struct CalibreLibraryCategory: Codable {
    var name: String
    var url: String
    var icon: String
    var is_category: Bool
}
