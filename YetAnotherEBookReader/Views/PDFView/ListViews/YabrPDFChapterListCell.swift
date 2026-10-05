//
//  YabrPDFChapterListCell.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/5.
//  Created by Heberti Almeida on 07/05/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
class YabrPDFChapterListCell: UITableViewCell {
    static let baseIndent: CGFloat = 15
    static let indentPerLevel: CGFloat = 16

    let indexLabel = UILabel()
    let pageLabel = UILabel()
    /// Indents the title by outline level (FolioReader prefixes spaces, which
    /// misaligns wrapped lines).
    private(set) var indexLeadingConstraint: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        layoutMargins = .zero
        preservesSuperviewLayoutMargins = false

        indexLabel.lineBreakMode = .byWordWrapping
        indexLabel.numberOfLines = 0
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(indexLabel)

        pageLabel.numberOfLines = 1
        pageLabel.textAlignment = .right
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        pageLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentView.addSubview(pageLabel)

        indexLeadingConstraint = indexLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.baseIndent)
        NSLayoutConstraint.activate([
            indexLeadingConstraint,
            indexLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            indexLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            pageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: indexLabel.trailingAnchor, constant: 8),
            pageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            pageLabel.firstBaselineAnchor.constraint(equalTo: indexLabel.firstBaselineAnchor),
            pageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }

    /// FolioReader's chapter row: the title shrinks with depth; the current
    /// chapter is in the accent colour, with no background.
    func configure(title: String, page: Int?, level: Int, isCurrent: Bool, style: PDFThemePalette.ListStyle) {
        indexLabel.text = title
        indexLabel.font = style.titleFont(level: level)
        indexLabel.textColor = isCurrent ? style.accent : style.text
        indexLeadingConstraint.constant = Self.baseIndent + Self.indentPerLevel * CGFloat(level)

        pageLabel.text = page.map { "p. \($0)" } ?? ""
        pageLabel.font = style.captionFont.withMonospacedDigits()
        pageLabel.textColor = isCurrent ? style.accent : style.secondaryText
    }
}

private extension UIFont {
    func withMonospacedDigits() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
