//
//  YabrPDFSearchList.swift
//  YetAnotherEBookReader
//

import UIKit
import PDFKit

@available(iOS 16.0, macCatalyst 16.0, *)
class YabrPDFSearchList: YabrPDFTableViewController, UISearchBarDelegate {
    let searchBar = UISearchBar()
    var searchResults = [PDFSelection]()
    var isSearching = false
    var currentQuery: String = ""
    let activityIndicator = UIActivityIndicatorView(style: .large)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tableView.register(YabrPDFSearchListCell.self, forCellReuseIdentifier: kReuseCellIdentifier)
        
        searchBar.delegate = self
        searchBar.placeholder = "Search in PDF"
        searchBar.sizeToFit()
        searchBar.searchBarStyle = .default
        
        // The field takes the system colours of the sheet's interface style.
        let style = listStyle
        searchBar.barTintColor = style.background
        searchBar.backgroundColor = style.background
        searchBar.backgroundImage = UIImage()
        searchBar.tintColor = style.accent
        searchBar.searchTextField.textColor = style.text
        searchBar.searchTextField.font = style.bodyFont
        
        self.tableView.tableHeaderView = searchBar
        
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    // MARK: - UISearchBarDelegate
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        guard let query = searchBar.text, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        isSearching = true
        currentQuery = query
        searchResults.removeAll()
        tableView.reloadData()
        activityIndicator.startAnimating()
        
        pdfViewController?.searchController.search(query: query) { [weak self] results in
            guard let self = self, self.currentQuery == query else { return }
            self.searchResults = results
            self.isSearching = false
            self.activityIndicator.stopAnimating()
            self.tableView.reloadData()
        }
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            self.searchResults.removeAll()
            self.currentQuery = ""
            self.tableView.reloadData()
        }
    }
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isSearching ? 0 : searchResults.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kReuseCellIdentifier, for: indexPath) as! YabrPDFSearchListCell
        
        guard indexPath.row < searchResults.count else { return cell }
        let selection = searchResults[indexPath.row]
        
        let style = listStyle

        if let page = selection.pages.first, let pageNum = page.pageRef?.pageNumber {
            var pageTitle = "Page \(pageNum)"
            if let outlineLabel = yabrPDFMetaSource?.yabrPDFOutline(yabrPDFView, for: pageNum)?.label, !outlineLabel.isEmpty {
                pageTitle += " - \(outlineLabel)"
            }
            cell.pageLabel.text = pageTitle
        } else {
            cell.pageLabel.text = "Unknown Page"
        }
        cell.pageLabel.font = style.captionFont
        cell.pageLabel.textColor = style.secondaryText

        cell.snippetLabel.attributedText = getPreview(for: selection, query: currentQuery, style: style)
        
        return cell
    }
    
    /// The match in context, marked as FolioReader's search marks it: heavier
    /// and in the accent colour.
    private func getPreview(for selection: PDFSelection, query: String, style: PDFThemePalette.ListStyle) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: style.bodyFont, .foregroundColor: style.text]
        guard let previewSelection = selection.copy() as? PDFSelection else {
            return NSAttributedString(string: selection.string ?? "", attributes: base)
        }
        previewSelection.extend(atStart: 25)
        previewSelection.extend(atEnd: 75)
        previewSelection.extendForLineBoundaries()
        
        let fullText = previewSelection.string ?? ""
        let cleanText = fullText.replacingOccurrences(of: "\n", with: " ")
        
        let attributed = NSMutableAttributedString(string: cleanText, attributes: base)
        let range = (cleanText as NSString).range(of: query, options: .caseInsensitive)
        if range.location != NSNotFound {
            attributed.addAttributes([
                .font: UIFont(name: "Avenir-Black", size: style.bodyFont.pointSize) ?? .boldSystemFont(ofSize: style.bodyFont.pointSize),
                .foregroundColor: style.accent,
            ], range: range)
        }
        return attributed
    }
    
    // MARK: - Table view delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.row < searchResults.count else { return }
        let selection = searchResults[indexPath.row]
        
        yabrPDFView?.go(to: selection)
        yabrPDFView?.setCurrentSelection(selection, animate: true)
        
        self.dismiss(animated: true)
    }
}
