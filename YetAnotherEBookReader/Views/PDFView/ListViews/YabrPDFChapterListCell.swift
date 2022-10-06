//
//  YabrPDFChapterListCell.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/5.
//  Created by Heberti Almeida on 07/05/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit

class YabrPDFChapterListCell: UITableViewCell {
    let indexLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.indexLabel.lineBreakMode = .byWordWrapping
        self.indexLabel.numberOfLines = 0
        self.indexLabel.translatesAutoresizingMaskIntoConstraints = false
        
        self.contentView.addSubview(indexLabel)

        // Configure cell contraints
        var constraints = [NSLayoutConstraint]()
        let views = ["label": indexLabel]

        NSLayoutConstraint.constraints(withVisualFormat: "H:|-15-[label]-15-|", options: [], metrics: nil, views: views).forEach {
            constraints.append($0 as NSLayoutConstraint)
        }

        NSLayoutConstraint.constraints(withVisualFormat: "V:|-16-[label]-16-|", options: [], metrics: nil, views: views).forEach {
            constraints.append($0 as NSLayoutConstraint)
        }

        self.contentView.addConstraints(constraints)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }
    
}
