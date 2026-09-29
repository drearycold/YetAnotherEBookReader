//
//  YabrPDFViewController+Selection.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFViewController {
    /// Installs the edit menus (see `PDFMenuManager`) and preloads the dictionary.
    func configureSelectionMenus() {
        menuManager.install()
        yabrPDFMetaSource?.yabrPDFDictViewer(pdfView)?.1.loadViewIfNeeded()
    }

    func addHighlight(style: BookHighlightStyle) {
        guard let currentSelection = pdfView.currentSelection else { return }
        annotationManager.addHighlight(style: style.rawValue, selection: currentSelection)
    }

    /// Writes or edits the note of an existing highlight.
    func presentNoteEditor(for highlightId: UUID, from presenter: UIViewController? = nil, onSaved: (() -> Void)? = nil) {
        guard let highlight = annotationManager.highlight(for: highlightId) else { return }
        let editor = YabrPDFNoteEditorViewController(
            quote: highlight.content,
            style: BookHighlightStyle(rawValue: highlight.type) ?? .yellow,
            note: highlight.note,
            palette: pdfOptions.themePalette
        )
        editor.onSave = { [weak self] note in
            self?.annotationManager.setNote(uuid: highlightId, note: note)
            onSaved?()
        }
        presentNoteEditor(editor, from: presenter ?? self)
    }

    /// Highlights the selection with a note; nothing is created unless a note is saved.
    func presentNoteEditorForSelection() {
        guard let selection = pdfView.currentSelection?.copy() as? PDFSelection,
              let text = selection.string, !text.isEmpty
        else { return }
        let editor = YabrPDFNoteEditorViewController(quote: text, style: .yellow, note: nil, palette: pdfOptions.themePalette)
        editor.onSave = { [weak self] note in
            guard let self, let note else { return }
            self.annotationManager.addHighlight(style: BookHighlightStyle.yellow.rawValue, selection: selection, note: note)
            self.pdfView.clearSelection()
        }
        presentNoteEditor(editor, from: self)
    }

    private func presentNoteEditor(_ editor: YabrPDFNoteEditorViewController, from presenter: UIViewController) {
        let nav = themedNavigationController(rootViewController: editor)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(nav, animated: true)
    }

    @objc func dictViewerAction(_ sender: Any?) {
        guard let selectedText = pdfView.currentSelection?.string,
              let (_, dictViewer) = yabrPDFMetaSource?.yabrPDFDictViewer(pdfView) else { return }

        dictViewer.title = selectedText
        present(dictViewer, animated: true)
    }
}
