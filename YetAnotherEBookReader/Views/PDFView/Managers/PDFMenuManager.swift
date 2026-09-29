//
//  PDFMenuManager.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

/// YabrPDF's edit menus, built from native menu elements:
/// - text selection: the reader actions are added to the system edit menu by
///   `YabrPDFView.buildMenu(with:)`;
/// - an existing highlight: its own menu, shown through a `UIEditMenuInteraction`.
@available(iOS 16.0, macCatalyst 16.0, *)
final class PDFMenuManager: NSObject {
    static let highlightMenuIdentifier = "yabr.pdf.highlight" as NSString

    enum ActionID {
        static let highlight = UIAction.Identifier("yabr.pdf.highlight")
        static let underline = UIAction.Identifier("yabr.pdf.underline")
        static let dictionary = UIAction.Identifier("yabr.pdf.dictionary")
        static let note = UIAction.Identifier("yabr.pdf.note")
        static let copyHighlight = UIAction.Identifier("yabr.pdf.highlight.copy")
        static let selectHighlight = UIAction.Identifier("yabr.pdf.highlight.select")
        static let deleteHighlight = UIAction.Identifier("yabr.pdf.highlight.delete")
        static func style(_ style: BookHighlightStyle) -> UIAction.Identifier {
            UIAction.Identifier("yabr.pdf.highlight.style.\(style.rawValue)")
        }
    }

    private weak var controller: YabrPDFViewController?
    private lazy var editMenuInteraction = UIEditMenuInteraction(delegate: self)
    /// View rect of the highlight whose menu is showing.
    private(set) var highlightMenuRect = CGRect.zero

    init(controller: YabrPDFViewController) {
        self.controller = controller
        super.init()
    }

    func install() {
        guard let pdfView = controller?.pdfView,
              !pdfView.interactions.contains(where: { $0 === editMenuInteraction })
        else { return }
        pdfView.addInteraction(editMenuInteraction)
    }

    // MARK: Text selection

    func selectionMenuElements() -> [UIMenuElement] {
        guard let controller else { return [] }

        var elements: [UIMenuElement] = [
            UIAction(title: "Highlight", image: UIImage(systemName: "paintbrush"), identifier: ActionID.highlight) { [weak controller] _ in
                controller?.addHighlight(style: .yellow)
            },
            UIAction(title: "Underline", image: UIImage(systemName: "highlighter"), identifier: ActionID.underline) { [weak controller] _ in
                controller?.addHighlight(style: .underline)
            },
            UIAction(title: "Note", image: UIImage(systemName: "note.text.badge.plus"), identifier: ActionID.note) { [weak controller] _ in
                controller?.presentNoteEditorForSelection()
            },
        ]
        if let (name, _) = controller.yabrPDFMetaSource?.yabrPDFDictViewer(controller.pdfView) {
            elements.append(
                UIAction(title: name.isEmpty ? "Dictionary" : name, image: UIImage(systemName: "character.book.closed"), identifier: ActionID.dictionary) { [weak controller] _ in
                    controller?.dictViewerAction(nil)
                }
            )
        }
        return elements
    }

    // MARK: Existing highlight

    func highlightMenuElements(for highlightId: UUID) -> [UIMenuElement] {
        guard let controller else { return [] }
        let pdfView = controller.pdfView
        let currentStyle = controller.annotationManager.style(of: highlightId)
        let hasNote = controller.annotationManager.note(of: highlightId) != nil

        let styles = BookHighlightStyle.allCases.map { style in
            UIAction(
                title: style.description,
                image: Self.swatch(for: style),
                identifier: ActionID.style(style),
                state: style == currentStyle ? .on : .off
            ) { [weak controller] _ in
                controller?.annotationManager.modifyHighlightStyle(uuid: highlightId, type: style)
            }
        }

        return [
            UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc"), identifier: ActionID.copyHighlight) { [weak pdfView] _ in
                pdfView?.copyHighlight(highlightId)
            },
            UIAction(title: "Select", image: UIImage(systemName: "text.cursor"), identifier: ActionID.selectHighlight) { [weak pdfView] _ in
                pdfView?.selectHighlight(highlightId)
            },
            UIAction(title: hasNote ? "Edit Note" : "Note", image: UIImage(systemName: "note.text"), identifier: ActionID.note) { [weak controller] _ in
                controller?.presentNoteEditor(for: highlightId)
            },
            UIMenu(title: "Style", image: UIImage(systemName: "paintpalette"), children: styles),
            UIAction(title: "Delete", image: UIImage(systemName: "trash"), identifier: ActionID.deleteHighlight, attributes: .destructive) { [weak controller] _ in
                controller?.annotationManager.removeHighlight(uuid: highlightId)
            },
        ]
    }

    func presentHighlightMenu(for highlightId: UUID, rect: CGRect) {
        guard let pdfView = controller?.pdfView else { return }
        install()
        pdfView.highlightTapped = highlightId
        highlightMenuRect = rect
        let configuration = UIEditMenuConfiguration(
            identifier: Self.highlightMenuIdentifier,
            sourcePoint: CGPoint(x: rect.midX, y: rect.minY)
        )
        editMenuInteraction.presentEditMenu(with: configuration)
    }

    func dismissHighlightMenu() {
        editMenuInteraction.dismissMenu()
    }

    private static func swatch(for style: BookHighlightStyle) -> UIImage? {
        let (subtype, color) = style.pdfAnnotationSubtype
        let symbol = subtype == .underline ? "underline" : "circle.fill"
        return UIImage(systemName: symbol)?.withTintColor(color, renderingMode: .alwaysOriginal)
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
extension PDFMenuManager: UIEditMenuInteractionDelegate {
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let highlightId = controller?.pdfView.highlightTapped else { return nil }
        return UIMenu(children: highlightMenuElements(for: highlightId))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        highlightMenuRect
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration, animator: UIEditMenuInteractionAnimating) {
        // Tapping another highlight presents its menu before this one finishes
        // dismissing; only clear the highlight this menu belonged to.
        let dismissed = controller?.pdfView.highlightTapped
        animator.addCompletion { [weak self] in
            guard let pdfView = self?.controller?.pdfView, pdfView.highlightTapped == dismissed else { return }
            pdfView.highlightTapped = nil
        }
    }
}
