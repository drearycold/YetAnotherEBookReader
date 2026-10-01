//
//  YabrPDFThumbnailListCell.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 07/05/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
class YabrPDFThumbnailListCell: UICollectionViewCell {
    let thumbImage = UIImageView()
    let titleLabel = UILabel()
    /// The page index this cell shows; an async thumbnail only lands if it
    /// still matches.
    var representedPage: Int?
    private var aspectConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.numberOfLines = 1
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        thumbImage.contentMode = .scaleAspectFill
        thumbImage.clipsToBounds = true
        thumbImage.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(thumbImage)
        contentView.addSubview(titleLabel)

        // The page hugs its image, so the border outlines the page itself.
        let fullWidth = thumbImage.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -32)
        fullWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            thumbImage.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            thumbImage.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            thumbImage.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -32),
            fullWidth,
            titleLabel.topAnchor.constraint(equalTo: thumbImage.bottomAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
        setAspect(3.0 / 4.0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }

    private func setAspect(_ ratio: CGFloat) {
        aspectConstraint?.isActive = false
        aspectConstraint = thumbImage.widthAnchor.constraint(equalTo: thumbImage.heightAnchor, multiplier: ratio)
        aspectConstraint?.isActive = true
    }

    func setThumbnail(_ image: UIImage?, pageAspect: CGFloat) {
        thumbImage.image = image
        if let aspectConstraint, abs(aspectConstraint.multiplier - pageAspect) < 0.001 { return }
        setAspect(pageAspect)
    }

    /// The current page is outlined and labelled in the accent colour, as the
    /// chapter list marks the current chapter.
    func configure(title: String, isCurrent: Bool, style: PDFThemePalette.ListStyle) {
        titleLabel.text = title
        titleLabel.font = style.captionFont
        titleLabel.textColor = isCurrent ? style.accent : style.secondaryText
        thumbImage.backgroundColor = style.secondaryText.withAlphaComponent(0.12)
        thumbImage.layer.borderColor = (isCurrent ? style.accent : style.separator).cgColor
        thumbImage.layer.borderWidth = isCurrent ? 2.5 : 1
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedPage = nil
        thumbImage.image = nil
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
class YabrPDFThumbnailSectionCell: UICollectionViewCell {
    let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.numberOfLines = 1
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }
}
