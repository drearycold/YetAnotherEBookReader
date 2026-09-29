//
//  YabrPDFNoteEditorViewController.swift
//  YetAnotherEBookReader
//

import UIKit

/// Writes or edits the note of a highlight: the highlighted text above a text
/// view, with Cancel / Save. Saving blank text clears the note.
@available(iOS 16.0, macCatalyst 16.0, *)
final class YabrPDFNoteEditorViewController: UIViewController {
    let quote: String
    let textView = UITextView()
    /// Called on Save with the trimmed note, or `nil` when it is blank.
    var onSave: ((String?) -> Void)?

    private let style: BookHighlightStyle
    private let initialNote: String?
    private let palette: PDFThemePalette?
    private let quoteLabel = UILabel()

    init(quote: String, style: BookHighlightStyle, note: String?, palette: PDFThemePalette? = nil) {
        self.quote = quote
        self.style = style
        self.initialNote = note
        self.palette = palette
        super.init(nibName: nil, bundle: nil)
        title = note == nil ? "Note" : "Edit Note"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let palette {
            overrideUserInterfaceStyle = palette.drawsInverted ? .dark : .light
            view.backgroundColor = palette.background.alpha > 0 ? UIColor(cgColor: palette.background) : .systemBackground
        } else {
            view.backgroundColor = .systemBackground
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.cancel()
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .save, primaryAction: UIAction { [weak self] _ in
            self?.save()
        })

        quoteLabel.translatesAutoresizingMaskIntoConstraints = false
        quoteLabel.numberOfLines = 3
        quoteLabel.attributedText = quotedText()

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        // Lines the text up with the quote above it.
        textView.textContainer.lineFragmentPadding = 0
        textView.text = initialNote
        textView.delegate = self

        view.addSubview(quoteLabel)
        view.addSubview(textView)
        let margins = view.layoutMarginsGuide
        NSLayoutConstraint.activate([
            quoteLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            quoteLabel.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            quoteLabel.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textView.topAnchor.constraint(equalTo: quoteLabel.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        textView.becomeFirstResponder()
    }

    func save() {
        onSave?(PDFAnnotationManager.normalizedNote(textView.text))
        dismiss(animated: true)
    }

    func cancel() {
        dismiss(animated: true)
    }

    private func quotedText() -> NSAttributedString {
        let text = quote.replacingOccurrences(of: "\n", with: " ")
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .subheadline),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let color = BookHighlightStyle.colorForStyle(style.rawValue, nightMode: palette?.drawsInverted ?? false)
        if style == .underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = color
        } else {
            attributes[.backgroundColor] = color
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFNoteEditorViewController: UITextViewDelegate {
    /// Keeps edited text from being swiped away with the sheet.
    func textViewDidChange(_ textView: UITextView) {
        isModalInPresentation = textView.text != (initialNote ?? "")
    }
}
