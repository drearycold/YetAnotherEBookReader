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
        ?? (self.parent as? YabrPDFNavigationPageVC)?.yabrPDFView
    }
    var yabrPDFMetaSource: YabrPDFMetaSource? {
        (self.parent as? YabrPDFAnnotationPageVC)?.yabrPDFMetaSource
        ?? (self.parent as? YabrPDFNavigationPageVC)?.yabrPDFMetaSource
    }
    var backgroundColor: UIColor? {
        guard let fillColor = yabrPDFMetaSource?.yabrPDFOptions(yabrPDFView)?.fillColor
        else { return nil }
        return UIColor(cgColor: fillColor)
    }
    var textColor: UIColor? {
        yabrPDFMetaSource?.yabrPDFOptions(yabrPDFView)?.isDark(.lightText, .darkText)
    }
    
    let dateFormatter = DateFormatter()
    
    var sections = [Int]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: kReuseHeaderFooterIdentifier)
        
        self.dateFormatter.dateStyle = .medium
        self.dateFormatter.timeStyle = .medium
        self.dateFormatter.doesRelativeDateFormatting = true
        
        self.tableView.separatorInset = UIEdgeInsets.zero
        self.tableView.backgroundColor = backgroundColor
        self.navigationController?.navigationBar.backgroundColor = backgroundColor
    }
    
    // MARK: - sections
    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section < sections.count else { return nil }
        
        guard let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: kReuseHeaderFooterIdentifier) else { return nil }
        
        let pageNumber = sections[section]
        var titleFrags = [String]()
        var pdfOutline = yabrPDFMetaSource?.yabrPDFOutline(yabrPDFView, for: pageNumber)
        while let label = pdfOutline?.label {
            if label.isEmpty == false {
                titleFrags.append(label)
            }
            pdfOutline = pdfOutline?.parent
        }
        if titleFrags.isEmpty {
            titleFrags.append("Page \(pageNumber)")
        }
        
        var headerContentConfiguration = headerView.defaultContentConfiguration()
        headerContentConfiguration.text = titleFrags.reversed().joined(separator: ", ")
        if let textColor = textColor {
            headerContentConfiguration.textProperties.color = textColor
        }
        headerView.contentConfiguration = headerContentConfiguration
        
        return headerView
    }
}
