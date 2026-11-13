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
    @Environment(\.presentationMode) private var presentationMode
    @Binding var bookURLs: [URL]
    var allowsMultipleSelection = true
    
    func makeCoordinator() -> BookImportPicker.Coordinator {
        return BookImportPicker.Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.epub, .pdf, .cbz], asCopy: true)
        #if CC3_UI_TEST_FIXTURE || FI1_UI_TEST_FIXTURE
        if ProcessInfo.processInfo.environment["YABR_CC3_LOCAL_FILE"] == "1" {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            #if FI1_UI_TEST_FIXTURE
            picker.directoryURL = documents?.appendingPathComponent("Incoming", isDirectory: true)
            #else
            picker.directoryURL = documents
            #endif
        }
        #endif
        picker.allowsMultipleSelection = allowsMultipleSelection
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
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.bookURLs.removeAll()
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

extension UTType {
    public static let cbz = UTType.init(exportedAs: "public.archive.cbz")
}
