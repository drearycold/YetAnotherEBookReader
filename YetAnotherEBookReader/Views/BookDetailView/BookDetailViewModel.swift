//
//  BookDetailViewModel.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/26.
//

import Foundation

class BookDetailViewModel: ObservableObject {
    
    var listVM: ReadingPositionListViewModel!
    
    init() {
        print("BookDetailViewModel INIT")
    }
}
