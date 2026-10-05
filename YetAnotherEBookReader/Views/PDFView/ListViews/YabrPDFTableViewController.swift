//
//  YabrPDFTableViewController.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/6.
//

import Foundation
import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
class YabrPDFTableViewController: UITableViewController {
    /// The reader of a list presented on its own (search), outside the
    /// Annotations / Navigations pages.
    weak var hostController: YabrPDFViewController?

    var pdfViewController: YabrPDFViewController? {
        (self.parent as? YabrPDFAnnotationPageVC)?.pdfViewController
        ?? (self.parent as? YabrPDFNavigationPageVC)?.pdfViewController
        ?? hostController
    }
    var yabrPDFView: YabrPDFView? {
        pdfViewController?.pdfView
    }
    var yabrPDFMetaSource: YabrPDFMetaSource? {
        (self.parent as? YabrPDFAnnotationPageVC)?.yabrPDFMetaSource
        ?? (self.parent as? YabrPDFNavigationPageVC)?.yabrPDFMetaSource
        ?? hostController?.yabrPDFMetaSource
    }
    /// The reader theme's list look (FolioReader's colours and fonts).
    var listStyle: PDFThemePalette.ListStyle {
        (pdfViewController?.pdfOptions.themePalette ?? PDFThemePalette(themeMode: .none)).listStyle
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
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 60
        applyListStyle()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // A list kept between presentations (search) follows a theme change.
        applyListStyle()
    }

    /// Colours from the reader's current theme; subclasses style their own views.
    func applyListStyle() {
        let style = listStyle
        tableView.backgroundColor = style.background
        tableView.separatorColor = style.separator
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
        let style = listStyle
        headerContentConfiguration.textProperties.color = style.secondaryText
        headerContentConfiguration.textProperties.font = style.captionFont
        headerView.contentConfiguration = headerContentConfiguration
        var background = UIBackgroundConfiguration.listPlainHeaderFooter()
        background.backgroundColor = style.background
        headerView.backgroundConfiguration = background
        
        return headerView
    }
}
