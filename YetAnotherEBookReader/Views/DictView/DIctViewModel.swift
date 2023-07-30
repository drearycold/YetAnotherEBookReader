//
//  DIctViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/7/29.
//

import Foundation
import WebKit

@MainActor class DictViewModel {
    
    var server: String?
    var word: String?

    var tabWebView: [WKWebView] = []
}
