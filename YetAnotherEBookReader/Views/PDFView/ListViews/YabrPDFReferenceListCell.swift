//
//  YabrPDFBookmarkListCell.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/5.
//

import Foundation
import UIKit

class YabrPDFReferenceListCell: UITableViewCell {
    let titleLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.backgroundColor = UIColor.clear

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 1
        
        contentView.addSubview(titleLabel)

        var constraints = [NSLayoutConstraint]()
        let views = ["title": titleLabel]
        
        constraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "H:|-[title]-|",
                metrics: nil,
                views: views
            )
        )
        constraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "V:|-[title]-|",
                metrics: nil,
                views: views
            )
        )
        
        contentView.addConstraints(constraints)
        
        layoutMargins = UIEdgeInsets.zero
        preservesSuperviewLayoutMargins = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
