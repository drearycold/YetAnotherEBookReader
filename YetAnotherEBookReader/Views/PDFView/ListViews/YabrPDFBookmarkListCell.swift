//
//  YabrPDFBookmarkListCell.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/5.
//

import Foundation
import UIKit

class YabrPDFBookmarkListCell: UITableViewCell {
    let dateLabel = UILabel()
    let titleLabel = UILabel()
    let titleField = UITextField()
    
    let titleSaveButton = UIButton()
    
    var titleLabelConstraints = [NSLayoutConstraint]()
    var titleFieldConstraints = [NSLayoutConstraint]()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.backgroundColor = UIColor.clear

//        dateLabel = UILabel(frame: CGRect(x: 0, y: 0, width: view.frame.width-40, height: 16))
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 12)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 1
        
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.isHidden = true
        
        titleSaveButton.translatesAutoresizingMaskIntoConstraints = false
        titleSaveButton.setTitle("Save", for: .normal)
        titleSaveButton.isHidden = true

        contentView.addSubview(dateLabel)
        contentView.addSubview(titleLabel)
        contentView.addSubview(titleField)
        contentView.addSubview(titleSaveButton)

        var constraints = [NSLayoutConstraint]()
        let views = ["date": dateLabel, "title": titleLabel, "titleField": titleField, "titleSave": titleSaveButton]
        
        constraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "H:|-15-[date]-[titleSave]-15-|",
                metrics: nil,
                views: views
            )
        )
        constraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "H:|-[title]-|",
                metrics: nil,
                views: views
            )
        )
        constraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "H:|-[titleField]-|",
                metrics: nil,
                views: views
            )
        )
        
        titleLabelConstraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "V:|-[date]-[title]-|",
                metrics: nil,
                views: views
            )
        )
        
        titleFieldConstraints.append(
            contentsOf: NSLayoutConstraint.constraints(
                withVisualFormat: "V:|-[date]-[titleField]-|",
                metrics: nil,
                views: views
            )
        )
        
        contentView.addConstraints(constraints)
        contentView.addConstraints(titleLabelConstraints)
        
        layoutMargins = UIEdgeInsets.zero
        preservesSuperviewLayoutMargins = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
