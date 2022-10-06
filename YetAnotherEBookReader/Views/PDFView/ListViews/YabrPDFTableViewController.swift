//
//  YabrPDFTableViewController.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/6.
//

import Foundation
import UIKit

class YabrPDFTableViewController: UITableViewController {
    var yabrPDFView: YabrPDFView? {
        (self.parent as? YabrPDFAnnotationPageVC)?.yabrPDFView
    }
    var yabrPDFMetaSource: YabrPDFMetaSource? {
        (self.parent as? YabrPDFAnnotationPageVC)?.yabrPDFMetaSource
    }
    
    let dateFormatter = DateFormatter()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.dateFormatter.dateStyle = .medium
        self.dateFormatter.timeStyle = .medium
        self.dateFormatter.doesRelativeDateFormatting = true
        
        self.tableView.separatorInset = UIEdgeInsets.zero
        if let fillColor = PDFPageWithBackground.fillColor {
            self.tableView.backgroundColor = UIColor(cgColor: fillColor)
        }
    }
}
