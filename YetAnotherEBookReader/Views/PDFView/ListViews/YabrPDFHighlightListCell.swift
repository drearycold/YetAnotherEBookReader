//
//  YabrPDFHighlightListCell.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/5.
//

import Foundation
import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
class YabrPDFHighlightListCell: UITableViewCell {
    let dateLabel: UILabel = .init()
    let highlightLabel: UILabel = .init()
    let noteLabel: UILabel = .init()
    private let stack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = UIColor.clear
        layoutMargins = UIEdgeInsets.zero
        preservesSuperviewLayoutMargins = false

        // As FolioReader's highlight list: the date above the whole marked text.
        highlightLabel.numberOfLines = 0
        noteLabel.numberOfLines = 3

        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        [dateLabel, highlightLabel, noteLabel].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(8, after: highlightLabel)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(highlight: PDFHighlight, date: String, style: PDFThemePalette.ListStyle) {
        dateLabel.text = date
        dateLabel.font = style.captionFont
        dateLabel.textColor = style.secondaryText

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        var attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraph,
            .font: style.bodyFont,
            .foregroundColor: style.highlightText,
        ]
        let highlightStyle = BookHighlightStyle(rawValue: highlight.type) ?? .yellow
        if highlightStyle == .underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = style.highlightFill(.underline)
        } else {
            attributes[.backgroundColor] = style.highlightFill(highlightStyle)
        }
        highlightLabel.attributedText = NSAttributedString(string: highlight.content, attributes: attributes)

        noteLabel.text = highlight.note
        noteLabel.font = style.bodyFont.withSize(14)
        noteLabel.textColor = style.secondaryText
        noteLabel.isHidden = highlight.note == nil
    }
}
