//
//  DocumentPicker.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/12.
//

import Foundation
import SwiftUI
import UIKit

struct FontImportPicker: UIViewControllerRepresentable {
    static let FakeURL = URL(fileURLWithPath: "/__FAKE__")

    @Binding var fontURLs: [URL]
    
    func makeCoordinator() -> FontImportPicker.Coordinator {
        return FontImportPicker.Coordinator(parent: self)
    }
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<FontImportPicker>) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.font], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: FontImportPicker.UIViewControllerType, context: UIViewControllerRepresentableContext<FontImportPicker>) {
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        
        var parent: FontImportPicker
        
        init(parent: FontImportPicker){
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.fontURLs = urls
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.fontURLs.removeAll()
            parent.fontURLs.append(FakeURL)   //to trigger onChange
        }
    }
}
