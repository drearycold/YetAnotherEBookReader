//
//  YabrPDFSearchList.swift
//  YetAnotherEBookReader
//

import UIKit
import PDFKit

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
        
        if let bgColor = backgroundColor {
            searchBar.barTintColor = bgColor
            searchBar.backgroundColor = bgColor
            searchBar.tintColor = textColor
            searchBar.searchTextField.textColor = textColor
            searchBar.searchTextField.backgroundColor = yabrPDFMetaSource?.yabrPDFOptionsIsNight(
                yabrPDFView,
                UIColor(white: 0.2, alpha: 1.0),
                UIColor(white: 0.9, alpha: 1.0)
            )
        }
        
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
            guard let self = self else { return }
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
        
        let textColor = self.textColor ?? UIColor.black
        let pageColor = yabrPDFMetaSource?.yabrPDFOptionsIsNight(
            yabrPDFView,
            UIColor(white: 0.7, alpha: 1.0),
            UIColor.darkGray
        ) ?? UIColor.darkGray
        
        if let page = selection.pages.first, let pageNum = page.pageRef?.pageNumber {
            var pageTitle = "Page \(pageNum)"
            if let outlineLabel = yabrPDFMetaSource?.yabrPDFOutline(yabrPDFView, for: pageNum)?.label, !outlineLabel.isEmpty {
                pageTitle += " - \(outlineLabel)"
            }
            cell.pageLabel.text = pageTitle
        } else {
            cell.pageLabel.text = "Unknown Page"
        }
        cell.pageLabel.textColor = pageColor
        
        // Generate snippet preview
        let previewText = getPreview(for: selection, query: currentQuery)
        let attributed = NSMutableAttributedString(attributedString: previewText)
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        
        cell.snippetLabel.attributedText = attributed
        
        return cell
    }
    
    private func getPreview(for selection: PDFSelection, query: String) -> NSAttributedString {
        guard let previewSelection = selection.copy() as? PDFSelection else {
            return NSAttributedString(string: selection.string ?? "")
        }
        previewSelection.extend(atStart: 25)
        previewSelection.extend(atEnd: 75)
        previewSelection.extendForLineBoundaries()
        
        let fullText = previewSelection.string ?? ""
        let cleanText = fullText.replacingOccurrences(of: "\n", with: " ")
        
        let attributed = NSMutableAttributedString(string: cleanText)
        let range = (cleanText as NSString).range(of: query, options: .caseInsensitive)
        if range.location != NSNotFound {
            attributed.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 14), range: range)
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
