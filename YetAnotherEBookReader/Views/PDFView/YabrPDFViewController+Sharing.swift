//
//  YabrPDFViewController+Sharing.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFViewController {
    func sharePDF(annotated: Bool) {
        let provider = YabrPDFSharingProvider(placeholderItem: "")
        guard let pdfURL = yabrPDFMetaSource?.yabrPDFURL(pdfView),
              let bookInShelfId = yabrPDFMetaSource?.yabrPDFBook(pdfView, info: "Key")
        else {
            return
        }

        let bookTitle = yabrPDFMetaSource?.yabrPDFBook(pdfView, info: "Title") ?? "No Title"
        let bookAuthor = yabrPDFMetaSource?.yabrPDFBook(pdfView, info: "Author") ?? "Unknown"

        let tmpDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(bookInShelfId, isDirectory: true)
        let tmpFile = tmpDir.appendingPathComponent("\(bookTitle) - \(bookAuthor).pdf", isDirectory: false)

        do {
            if false == FileManager.default.fileExists(atPath: tmpDir.path) {
                try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: false)
            }
            if FileManager.default.fileExists(atPath: tmpFile.path) {
                try FileManager.default.removeItem(at: tmpFile)
            }
            if annotated {
                guard writeAnnotatedPDF(to: tmpFile)
                else {
                    return
                }
            } else {
                try FileManager.default.linkItem(at: pdfURL, to: tmpFile)
            }
        } catch {
            print("Save Original PDF error=\(error)")
            let alert = UIAlertController(title: "Error Sharing PDF", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(.init(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        provider.fileURL = tmpFile
        provider.subject = "Save Original PDF"

        let vc = UIActivityViewController(activityItems: [provider], applicationActivities: nil)
        if let popover = vc.popoverPresentationController {
            popover.barButtonItem = shareBarButtonItem
        }

        present(vc, animated: true, completion: nil)
    }

    /// Writes the document with its highlights; notes travel as the highlights'
    /// comments. The page theme is not rendered.
    func writeAnnotatedPDF(to url: URL) -> Bool {
        pdfView.annotatedExportDocument()?.write(to: url) == true
    }
}
