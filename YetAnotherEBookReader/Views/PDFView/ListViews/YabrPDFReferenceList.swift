//
//  FolioReaderBookmarkList.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 01/09/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import SwiftSoup

class YabrPDFReferenceList: YabrPDFTableViewController {
    fileprivate var sectionBookmarks = [Int: [PDFBookmark]]()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.register(YabrPDFReferenceListCell.self, forCellReuseIdentifier: kReuseCellIdentifier)
        
        loadSections()
    }

    func loadSection() -> [PDFBookmark] {
        var bookmarks = [PDFBookmark]()

        return bookmarks
    }
    
    func loadSections() {
        guard let refText = yabrPDFMetaSource?.yabrPDFReferenceText(yabrPDFView)
        else { return }
        
        
    }
    
    // MARK: - Table view data source

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kReuseCellIdentifier, for: indexPath) as! YabrPDFReferenceListCell

        guard let bookmark = sectionBookmarks[sections[indexPath.section]]?[indexPath.row] else {
            return cell
        }

        cell.titleLabel.textColor = yabrPDFMetaSource?.yabrPDFOptionsIsNight(
            yabrPDFView,
            UIColor.lightGray,
            UIColor.black
        )
        cell.titleLabel.text = bookmark.title
        
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 40
    }
    
    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let bookmark = sectionBookmarks[sections[indexPath.section]]?[indexPath.row]
        else { return }
        
        yabrPDFMetaSource?.yabrPDFNavigate(yabrPDFView, pageNumber: bookmark.pos.page, offset: bookmark.pos.offset)
    }

    // MARK: - Handle rotation transition
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        tableView.reloadData()
    }
    
}
