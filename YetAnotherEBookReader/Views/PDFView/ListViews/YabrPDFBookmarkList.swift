//
//  YabrPDFBookmarkList.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/5.
//  Created by Heberti Almeida on 01/09/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.

import UIKit
import PDFKit

class YabrPDFBookmarkList: YabrPDFTableViewController {
    fileprivate var sections = [Int]()
    fileprivate var sectionBookmarks = [Int: [PDFBookmark]]()   //Page to Bookmark

    fileprivate var editingBookmark: IndexPath?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.register(YabrPDFBookmarkListCell.self, forCellReuseIdentifier: kReuseCellIdentifier)
        
        loadSections()
    }

    func loadSections() {
        guard let bookmarks = yabrPDFMetaSource?.yabrPDFBookmarks(yabrPDFView)
        else { return }
        
        sectionBookmarks = bookmarks.reduce(into: [:]) { partialResult, bookmark in
            let sectionKey = self.yabrPDFMetaSource?.yabrPDFOutline(yabrPDFView, for: bookmark.page)?.destination?.page?.pageRef?.pageNumber ?? bookmark.page
            
            if partialResult[sectionKey] != nil {
                partialResult[sectionKey]?.append(bookmark)
                partialResult[sectionKey]?.sort(by: {
                    if $0.page != $1.page { return $0.page < $1.page }
                    return $0.offset.y < $1.offset.y
                })
            } else {
                partialResult[sectionKey] = [bookmark]
            }
        }
        
        sections = sectionBookmarks.keys.sorted()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Jump to the current chapter
        DispatchQueue.main.async {
            guard let viewController = self.presentingViewController as? YabrPDFViewController,
                  let currentPageNumber = viewController.pdfView.currentPage?.pageRef?.pageNumber,
                  let sectionPageNumber = self.sections.filter({ $0 <= currentPageNumber }).last,
                  let section = self.sections.firstIndex(of: sectionPageNumber)
            else { return }
            self.tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: true)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sectionBookmarks[sections[section]]?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let pageNumber = sections[section]
        var titleFrags = [String]()
        var pdfOutline = yabrPDFMetaSource?.yabrPDFOutline(yabrPDFView, for: pageNumber)
        while let label = pdfOutline?.label {
            titleFrags.append(label)
            pdfOutline = pdfOutline?.parent
        }
        if titleFrags.isEmpty {
            titleFrags.append("Page \(pageNumber)")
        }
        
        return "  " + titleFrags.reversed().joined(separator: ", ")
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> YabrPDFBookmarkListCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kReuseCellIdentifier, for: indexPath) as! YabrPDFBookmarkListCell

        guard let bookmark = sectionBookmarks[sections[indexPath.section]]?[indexPath.row] else {
            return cell
        }

        cell.dateLabel.text = dateFormatter.string(from: bookmark.date).uppercased()
        cell.dateLabel.textColor = yabrPDFMetaSource?.yabrPDFOptionsIsNight(
            yabrPDFView,
            UIColor(white: 5, alpha: 0.3),
            UIColor.lightGray
        )
        cell.titleLabel.textColor = yabrPDFMetaSource?.yabrPDFOptionsIsNight(
            yabrPDFView,
            UIColor.lightGray,
            UIColor.black
        )
        cell.titleLabel.text = bookmark.title
        
        cell.titleField.textColor = yabrPDFMetaSource?.yabrPDFOptionsIsNight(
            yabrPDFView,
            UIColor.lightGray,
            UIColor.black
        )
        
        cell.titleField.text = bookmark.title
        cell.titleField.sizeToFit()
        
        cell.titleSaveButton.removeTarget(self, action: nil, for: .primaryActionTriggered)
        cell.titleSaveButton.addTarget(self, action: #selector(saveBookmarkTitleAction(_:)), for: .primaryActionTriggered)
        
        if indexPath == editingBookmark {
            cell.titleLabel.isHidden = true
            cell.titleField.isHidden = false
            cell.titleSaveButton.isHidden = false
            cell.titleField.becomeFirstResponder()
        }
        
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let bookmark = sectionBookmarks[sections[indexPath.section]]?[indexPath.row] else {
            return 0.0
        }

        let cleanString = bookmark.title
        let text = NSMutableAttributedString(string: cleanString)
        let range = NSRange(location: 0, length: text.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        text.addAttribute(NSAttributedString.Key.paragraphStyle, value: paragraph, range: range)
        text.addAttribute(NSAttributedString.Key.font, value: UIFont(name: "Avenir-Light", size: 16)!, range: range)

        let s = text.boundingRect(with: CGSize(width: view.frame.width-40, height: CGFloat.greatestFiniteMagnitude),
                                  options: [NSStringDrawingOptions.usesLineFragmentOrigin, NSStringDrawingOptions.usesFontLeading],
                                  context: nil)

        let totalHeight = s.size.height + 66
        
        return totalHeight
    }
    
    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let bookmark = sectionBookmarks[sections[indexPath.section]]?[indexPath.row]
        else { return }
        
        yabrPDFMetaSource?.yabrPDFNavigate(yabrPDFView, pageNumber: bookmark.page, offset: bookmark.offset)
        
        self.dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let bookmark = sectionBookmarks[sections[indexPath.section]]?[indexPath.row]
            else { return }

            yabrPDFMetaSource?.yabrPDFBookmarks(yabrPDFView, remove: bookmark)
            
            sectionBookmarks[sections[indexPath.section]]?.remove(at: indexPath.row)
            if sectionBookmarks[sections[indexPath.section]]?.isEmpty == true, sections.count > 1 {
                sectionBookmarks.removeValue(forKey: sections[indexPath.section])
                sections.remove(at: indexPath.section)
            }
            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }
    
    
    // MARK: - Handle rotation transition
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        tableView.reloadData()
    }
    
    func addBookmark(completion: (() -> Void)? = nil) {
        defer {
            completion?()
        }
        guard let destination = yabrPDFView?.currentDestination,
              let pageNumber = destination.page?.pageRef?.pageNumber
        else {
            return
        }
        
        yabrPDFMetaSource?.yabrPDFBookmarks(
            yabrPDFView,
            update: PDFBookmark(
                page: pageNumber,
                offset: destination.point,
                title: yabrPDFMetaSource?.yabrPDFOutline(yabrPDFView, for: pageNumber)?.label ?? "Page \(pageNumber)",
                date: Date()
            )
        )
        
        self.loadSections()
        self.tableView.reloadData()
    }
    
    @objc func saveBookmarkTitleAction(_ sender: UIButton) {
        guard let editingBookmark = editingBookmark else {
            return
        }

        guard let cell = self.tableView.cellForRow(at: editingBookmark) as? YabrPDFBookmarkListCell,
              let title = cell.titleField.text else { return }

        //TODO: updating
    }
}
