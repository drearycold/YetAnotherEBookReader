//
//  YabrPDFThumbnailListCell.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 07/05/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit

class YabrPDFThumbnailListCell: UICollectionViewCell {
    let thumbImage = UIImageView()
    let titleLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.titleLabel.numberOfLines = 1
        self.titleLabel.textAlignment = .center
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.font = .systemFont(ofSize: 12)

        self.thumbImage.contentMode = .scaleAspectFit
        self.thumbImage.translatesAutoresizingMaskIntoConstraints = false

        self.contentView.addSubview(self.thumbImage)
        self.contentView.addSubview(self.titleLabel)
        
        var constraints = [NSLayoutConstraint]()
        let views = ["thumb": thumbImage, "title": titleLabel]

        NSLayoutConstraint.constraints(withVisualFormat: "V:|-[thumb]-[title]-|", options: [], metrics: nil, views: views).forEach {
            constraints.append($0 as NSLayoutConstraint)
        }

        NSLayoutConstraint.constraints(withVisualFormat: "H:|-16-[thumb]-16-|", options: [], metrics: nil, views: views).forEach {
            constraints.append($0 as NSLayoutConstraint)
        }
        
        NSLayoutConstraint.constraints(withVisualFormat: "H:|-16-[title]-16-|", options: [], metrics: nil, views: views).forEach {
            constraints.append($0 as NSLayoutConstraint)
        }

        self.contentView.addConstraints(constraints)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }
}

class YabrPDFThumbnailSectionCell: UICollectionViewCell {
    let titleLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.titleLabel.numberOfLines = 1
        self.titleLabel.textAlignment = .center
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false

        self.contentView.addSubview(self.titleLabel)
        
        var constraints = [NSLayoutConstraint]()
        let views = ["title": titleLabel]

        NSLayoutConstraint.constraints(withVisualFormat: "V:|-[title]-|", options: [], metrics: nil, views: views).forEach {
            constraints.append($0 as NSLayoutConstraint)
        }

        NSLayoutConstraint.constraints(withVisualFormat: "H:|-16-[title]-16-|", options: [], metrics: nil, views: views).forEach {
            constraints.append($0 as NSLayoutConstraint)
        }

        self.contentView.addConstraints(constraints)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }
}
