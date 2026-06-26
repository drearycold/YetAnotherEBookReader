//
//  ShelfDisplayModels.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-22.
//

import Foundation

public enum ShelfBookStatus: String, Codable, Equatable, CaseIterable {
    case ready
    case noConnect
    case hasUpdate
    case downloading
    case local
    case updating
}

public struct ShelfBookItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let coverURL: String
    public let progress: Int
    public let status: ShelfBookStatus
    
    public init(id: String, title: String, coverURL: String, progress: Int, status: ShelfBookStatus) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.progress = progress
        self.status = status
    }
}

public struct ShelfSectionItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let books: [ShelfBookItem]
    
    public init(id: String, title: String, books: [ShelfBookItem]) {
        self.id = id
        self.title = title
        self.books = books
    }
}

public struct ShelfLibraryFilterItem: Identifiable, Equatable {
    public let id: String
    public let name: String
    public var serverName: String
    public var isSelected: Bool
    
    public init(id: String, name: String, serverName: String, isSelected: Bool) {
        self.id = id
        self.name = name
        self.serverName = serverName
        self.isSelected = isSelected
    }
}

public struct ShelfSelectionState: Equatable {
    public var selectedBookIds: Set<String> = []
    public var isEditing: Bool = false
    
    public init(selectedBookIds: Set<String> = [], isEditing: Bool = false) {
        self.selectedBookIds = selectedBookIds
        self.isEditing = isEditing
    }
}


