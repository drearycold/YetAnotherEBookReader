//
//  ReaderView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/26.
//

import Foundation
import UIKit
import SwiftUI

@available(macCatalyst 14.0, *)
struct ReaderViewController: UIViewControllerRepresentable {
    let vc = FolioReaderViewController()
    
    func makeUIViewController(context: Context) -> FolioReaderViewController {
        //vc.folioReader = FolioReader()
        return vc
    }
    
    func updateUIViewController(_ uiViewController: FolioReaderViewController, context: Context) {
            
    }
    
    func openBook(_ bookURL : URL, _ bookDetailView: BookDetailView) {
        vc.bookDetailView = bookDetailView
        vc.folioReader = FolioReader()
        vc.open(epubURL: bookURL)
    }
}
