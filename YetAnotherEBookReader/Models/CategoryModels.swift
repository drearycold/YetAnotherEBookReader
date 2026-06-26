//
//  CategoryModels.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-12.
//

import Foundation

struct LibraryCategoryItem: Equatable, Sendable, Codable {
    let name: String
    let averageRating: Double
    let count: Int
    let url: String
}

struct LibraryCategoryResult: Equatable, Sendable {
    let libraryId: String
    let categoryName: String
    let items: [LibraryCategoryItem]
    let generation: Date
    let totalNumber: Int
}

struct UnifiedCategoryItem: Equatable, Sendable, Identifiable {
    var id: String { name }
    let categoryName: String
    let name: String
    let averageRating: Double
    let count: Int
    let libraryItems: [String: LibraryCategoryItem] // libraryId -> LibraryCategoryItem
}

struct UnifiedCategoryResult: Equatable, Sendable {
    let categoryName: String
    let search: String
    let totalNumber: Int
    let itemsCount: Int
    let items: [UnifiedCategoryItem]
}

struct CategoryCacheSummary: Equatable, Sendable, Identifiable {
    var id: String { categoryName }
    let categoryName: String
    let itemsCount: Int
    let totalNumber: Int
}

