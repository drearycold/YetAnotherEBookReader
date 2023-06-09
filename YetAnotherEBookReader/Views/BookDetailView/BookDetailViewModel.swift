//
//  BookDetailViewModel.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/26.
//

import Foundation

extension BookDetailView {
    @MainActor class ViewModel: ObservableObject {
        
    }
}

class BookDetailViewModel: ObservableObject {
    
    var listVM: ReadingPositionListViewModel!
    
    init() {
        print("BookDetailViewModel INIT")
    }
}
