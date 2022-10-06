//
//  YabrPDFHighlightListCell.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/5.
//

import Foundation
import UIKit

class YabrPDFHighlightListCell: UITableViewCell {
    let dateLabel: UILabel = .init()
    let highlightLabel: UILabel = .init()
    let noteLabel: UILabel = .init()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = UIColor.clear
        layoutMargins = UIEdgeInsets.zero
        preservesSuperviewLayoutMargins = false
        
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 12)
        
        highlightLabel.translatesAutoresizingMaskIntoConstraints = false
        highlightLabel.font = .systemFont(ofSize: 13)
        highlightLabel.numberOfLines = 2
        
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        noteLabel.numberOfLines = 2
        noteLabel.font = .systemFont(ofSize: 14)
        noteLabel.textColor = .gray

        contentView.addSubview(dateLabel)
        contentView.addSubview(highlightLabel)
        contentView.addSubview(noteLabel)

//        dateLabel.frame = CGRect(x: 20, y: 20, width: view.frame.width-40, height: dateLabel.frame.height)
//        highlightLabel.frame = CGRect(x: 20, y: 46, width: view.frame.width-40, height: highlightLabel.frame.height)
//        noteLabel.frame = CGRect(x: 20, y: 46 + highlightLabel.frame.height + 10, width: view.frame.width-40, height: noteLabel.frame.height)

        var constraints = [NSLayoutConstraint]()
        let views = ["date": dateLabel, "content": highlightLabel, "note": noteLabel]
        
        constraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "H:|-15-[date]-15-|",
                metrics: nil,
                views: views
            )
        )
        constraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "H:|-[content]-|",
                metrics: nil,
                views: views
            )
        )
        constraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "H:|-[note]-|",
                metrics: nil,
                views: views
            )
        )
        
        constraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "V:|-[date]-[content]-[note]-|",
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
