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

    static let historyCellIdentifier = "io.github.drearycold.DSReader.Cell.SearchHistory"
    /// This reader session's queries (the list lives as long as the reader).
    var searchHistory = PDFSearchHistory()
    var history: [String] { searchHistory.queries }
    /// As FolioReader: an empty search bar lists the recent searches.
    var isShowingHistory: Bool {
        (searchBar.text ?? "").isEmpty && !isSearching
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tableView.register(YabrPDFSearchListCell.self, forCellReuseIdentifier: kReuseCellIdentifier)
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.historyCellIdentifier)
        
        searchBar.delegate = self
        searchBar.placeholder = "Search in PDF"
        searchBar.sizeToFit()
        searchBar.searchBarStyle = .default
        searchBar.backgroundImage = UIImage()
        applyListStyle()

        self.tableView.tableHeaderView = searchBar
        
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    /// The field takes the system colours of the sheet's interface style; the
    /// rest follows the reader theme, also when it changed since the last time.
    override func applyListStyle() {
        super.applyListStyle()
        let style = listStyle
        searchBar.barTintColor = style.background
        searchBar.backgroundColor = style.background
        searchBar.tintColor = style.accent
        searchBar.searchTextField.textColor = style.text
        searchBar.searchTextField.font = style.bodyFont
        if isViewLoaded {
            tableView.reloadData()
        }
    }

    /// Kept once a result of it is opened, as FolioReader records queries.
    func recordCurrentQuery() {
        searchHistory.record(currentQuery)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A new search starts typing; a kept one shows its results.
        if currentQuery.isEmpty {
            searchBar.becomeFirstResponder()
        }
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
        }
        // Switches between the recent searches and the results.
        self.tableView.reloadData()
    }
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isShowingHistory {
            return history.count
        }
        return isSearching ? 0 : searchResults.count
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard isShowingHistory, !history.isEmpty,
              let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: kReuseHeaderFooterIdentifier)
        else { return nil }
        let style = listStyle
        var content = headerView.defaultContentConfiguration()
        content.text = "Recent Searches"
        content.textProperties.color = style.secondaryText
        content.textProperties.font = style.captionFont
        headerView.contentConfiguration = content
        var background = UIBackgroundConfiguration.listPlainHeaderFooter()
        background.backgroundColor = style.background
        headerView.backgroundConfiguration = background
        return headerView
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        isShowingHistory && !history.isEmpty ? UITableView.automaticDimension : 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isShowingHistory {
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.historyCellIdentifier, for: indexPath)
            let style = listStyle
            var content = cell.defaultContentConfiguration()
            content.text = history[indexPath.row]
            content.textProperties.font = style.bodyFont
            content.textProperties.color = style.text
            cell.contentConfiguration = content
            cell.backgroundColor = .clear
            return cell
        }
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
        if isShowingHistory {
            guard indexPath.row < history.count else { return }
            tableView.deselectRow(at: indexPath, animated: true)
            searchBar.text = history[indexPath.row]
            searchBarSearchButtonClicked(searchBar)
            return
        }
        guard indexPath.row < searchResults.count else { return }
        let selection = searchResults[indexPath.row]
        recordCurrentQuery()

        yabrPDFView?.go(to: selection)
        yabrPDFView?.setCurrentSelection(selection, animate: true)
        
        self.dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard isShowingHistory, indexPath.row < history.count else { return nil }
        let query = history[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else { return completion(false) }
            self.searchHistory.remove(query)
            tableView.deleteRows(at: [indexPath], with: .fade)
            if self.history.isEmpty {
                tableView.reloadData()
            }
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
