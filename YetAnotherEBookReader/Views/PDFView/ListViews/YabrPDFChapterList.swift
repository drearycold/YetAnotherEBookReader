//
//  FolioReaderChapterList.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 15/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import PDFKit

@available(iOS 16.0, macCatalyst 16.0, *)
class YabrPDFChapterList: YabrPDFTableViewController {
    fileprivate var outlines = [PDFOutline]()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Register cell classes
        self.tableView.register(YabrPDFChapterListCell.self, forCellReuseIdentifier: kReuseCellIdentifier)
        
        // Create TOC list
        loadItems()
    }

    func loadItems() {
        outlines.removeAll()
        
        guard let pdfDoc = yabrPDFMetaSource?.yabrPDFDocument(yabrPDFView),
              let outlineRoot = pdfDoc.outlineRoot
        else {
            return
        }

        var stack = [outlineRoot]
        while stack.isEmpty == false {
            let outline = stack.removeLast()
            if outline != outlineRoot {
                outlines.append(outline)
            }
            for i in (0..<outline.numberOfChildren).reversed() {
                guard let child = outline.child(at: i) else { return }
                stack.append(child)
            }
        }
    }
    
    /// The chapter being read: the last outline that starts on or before
    /// `currentPage` (pages are 1-based). A chapter's first page belongs to it
    /// only, not also to the one before. `nil` before the first chapter.
    static func currentIndex(startPages: [Int?], currentPage: Int) -> Int? {
        var current: Int?
        for (index, start) in startPages.enumerated() {
            guard let start else { continue }
            if start <= currentPage {
                current = index
            } else if current != nil {
                break
            }
        }
        return current
    }

    var currentOutlineIndex: Int? {
        guard let currentPageNumber = yabrPDFView?.currentPage?.pageRef?.pageNumber else { return nil }
        return Self.currentIndex(
            startPages: outlines.map { $0.destination?.page?.pageRef?.pageNumber },
            currentPage: currentPageNumber
        )
    }

    /// The list is built for one presentation; the page does not change under it.
    private lazy var currentRow: Int? = currentOutlineIndex

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let index = currentRow else { return }
        self.tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return outlines.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kReuseCellIdentifier, for: indexPath) as! YabrPDFChapterListCell

        let outline = outlines[indexPath.row]

        var outlineLevel = 0
        var outlineParent = outline.parent
        while outlineParent != nil {
            outlineLevel += 1
            outlineParent = outlineParent?.parent
        }

        cell.configure(
            title: outline.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No Label",
            page: outline.destination?.page?.pageRef?.pageNumber,
            level: max(outlineLevel - 1, 0),
            isCurrent: indexPath.row == currentRow,
            style: listStyle
        )
        return cell
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0.0
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let outline = outlines[indexPath.row]
        
        guard let destination = outline.destination else { return }
        
        yabrPDFMetaSource?.yabrPDFNavigate(yabrPDFView, destination: destination)
        
        self.dismiss(animated: true)
    }
}
