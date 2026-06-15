//
//  YabrPDFSearchListCell.swift
//  YetAnotherEBookReader
//

import Foundation
import UIKit

class YabrPDFSearchListCell: UITableViewCell {
    let pageLabel: UILabel = .init()
    let snippetLabel: UILabel = .init()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = UIColor.clear
        layoutMargins = UIEdgeInsets.zero
        preservesSuperviewLayoutMargins = false
        
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.font = .boldSystemFont(ofSize: 12)
        
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false
        snippetLabel.font = .systemFont(ofSize: 14)
        snippetLabel.numberOfLines = 3
        
        contentView.addSubview(pageLabel)
        contentView.addSubview(snippetLabel)
        
        var constraints = [NSLayoutConstraint]()
        let views = ["page": pageLabel, "snippet": snippetLabel]
        
        constraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "H:|-15-[page]-15-|",
                metrics: nil,
                views: views
            )
        )
        constraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "H:|-15-[snippet]-15-|",
                metrics: nil,
                views: views
            )
        )
        constraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "V:|-10-[page]-[snippet]-10-|",
                metrics: nil,
                views: views
            )
        )
        
        contentView.addConstraints(constraints)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
