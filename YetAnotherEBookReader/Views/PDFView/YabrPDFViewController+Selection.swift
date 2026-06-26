//
//  YabrPDFViewController+Selection.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

@available(macCatalyst 14.0, *)
extension YabrPDFViewController {
    func buildDefaultMenuItems() -> [UIMenuItem] {
        let highlightMenuItem = UIMenuItem(title: "HighlightA", action: #selector(highlightAction(_:)))

        var menuItems = [highlightMenuItem]

        if let dictViewer = yabrPDFMetaSource?.yabrPDFDictViewer(pdfView) {
            let dictViewerItem = UIMenuItem(title: "MDict", image: UIImage(systemName: "character.book.closed")) { [weak self] _ in
                self?.dictViewerAction(self)
            }
//            menuItems.append(UIMenuItem(title: dictViewer.0, action: #selector(dictViewerAction)))
            menuItems.append(dictViewerItem)
            dictViewer.1.loadViewIfNeeded()
        }

        return menuItems
    }

    @objc func highlightAction(_ sender: Any?) {
        if pdfView.highlightTapped != nil {

        } else {
            guard let currentSelection = pdfView.currentSelection else { return }

            var style = BookHighlightStyle.yellow.rawValue
            if (sender as? UIButton) == annotationView.underlineButton {
                style = BookHighlightStyle.underline.rawValue
            }

            annotationManager.addHighlight(style: style, selection: currentSelection)
            annotationView.isHidden = true
        }
    }

    @objc func dictViewerAction(_ sender: Any?) {
        guard let selectedText = pdfView.currentSelection?.string,
              let (_, dictViewer) = yabrPDFMetaSource?.yabrPDFDictViewer(pdfView) else { return }

        print("\(#function) word=\(selectedText)")
        dictViewer.title = selectedText

        present(dictViewer, animated: true)
    }
}

@available(iOS 16.0, *)
extension YabrPDFViewController: UIEditMenuInteractionDelegate {
    @objc func didLongPress(_ recognizer: UIGestureRecognizer) {
        let location = recognizer.location(in: pdfView)

        let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: location)

        guard let interaction = pdfView.interactions.first(where: { (($0 as? UIEditMenuInteraction)?.delegate as? YabrPDFViewController) == self }) as? UIEditMenuInteraction
        else {
            return
        }

//        let aoi = pdfView.areaOfInterest(for: location)
//        guard aoi.contains(.textArea)
//        else { return }

        pdfView.visiblePages.forEach { page in
            let pagePoint = pdfView.convert(location, to: page)
            if let pageSelection = pdfView.currentPage?.selectionForWord(at: pagePoint) {
                pdfView.setCurrentSelection(pageSelection, animate: true)
                print("\(#function) selection=\(pageSelection)")
            }
        }

        // Present the edit menu interaction.
        interaction.presentEditMenu(with: configuration)
    }
}
