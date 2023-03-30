//
//  LibraryInfoViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/3/30.
//

import Foundation

extension LibraryInfoView {
    @MainActor class ViewModel: ObservableObject {
        @Published var categoriesSelected: String? = nil
        @Published var categoryItemSelected: String? = nil
        
        @Published var categoryName: String = ""
        @Published var categoryFilter: String = ""
        @Published var categoryItems: [String] = []
        
        @Published var lastSortCriteria: [LibrarySearchSort] = []
        
        @Published var categoryFilterString: String = ""
        
        let categoryItemsTooLong = ["__TOO_LONG__CATEGORY_LIST__"]
        
    }
}
