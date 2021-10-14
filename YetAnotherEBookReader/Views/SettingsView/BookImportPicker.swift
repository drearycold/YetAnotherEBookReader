//
//  DocumentPicker.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/12.
//

import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BookImportPicker: UIViewControllerRepresentable {
    @Binding var bookURLs: [URL]
    
    func makeCoordinator() -> BookImportPicker.Coordinator {
        return BookImportPicker.Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.epub, .pdf, .cbz], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        
        var parent: BookImportPicker
        
        init(parent: BookImportPicker){
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.bookURLs = urls
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.bookURLs.removeAll()
        }
    }
}

extension UTType {
    public static let cbz = UTType.init(exportedAs: "public.archive.cbz")
}
