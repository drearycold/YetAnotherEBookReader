//
//  FolioReaderChapterList.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 15/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import PDFKit

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
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        guard let currentPageNumber = yabrPDFView?.currentPage?.pageRef?.pageNumber else { return }

        var outlineIndex = outlines.endIndex - 1
        for i in 0..<(outlines.count-1) {
            if (outlines[i].destination?.page?.pageRef?.pageNumber ?? 0) <= currentPageNumber,
               (outlines[i+1].destination?.page?.pageRef?.pageNumber ?? 0) >= currentPageNumber {
                outlineIndex = i
                break
            }
        }
        
        self.tableView.scrollToRow(at: IndexPath(row: outlineIndex, section: 0), at: .middle, animated: true)
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
        let isSection = outline.numberOfChildren > 0

        var outlineLevel = 0
        var outlineParent = outline.parent
        while outlineParent != nil {
            outlineLevel += 1
            outlineParent = outlineParent?.parent
        }
        
        let indentCount = max(outlineLevel - 1, 0)
        cell.indexLabel.text = Array.init(repeating: " ", count: indentCount * 2).joined() + (outline.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No Label")
        cell.indexLabel.textColor = textColor

        if let pageNumber = outline.destination?.page?.pageRef?.pageNumber {
            cell.pageLabel.text = "p. \(pageNumber)"
        } else {
            cell.pageLabel.text = ""
        }
        cell.pageLabel.textColor = .darkGray
        
        // TODO: Mark current reading chapter
        
        cell.layoutMargins = UIEdgeInsets.zero
        cell.preservesSuperviewLayoutMargins = false
        cell.contentView.backgroundColor = isSection ? UIColor(white: 0.7, alpha: 0.1) : UIColor.clear
        cell.backgroundColor = UIColor.clear
        
        if indexPath.row + 1 == outlines.endIndex {
            cell.backgroundColor = .lightGray
        } else if let currentPageNumber = yabrPDFView?.currentPage?.pageRef?.pageNumber,
                  (outlines[indexPath.row].destination?.page?.pageRef?.pageNumber ?? 0) <= currentPageNumber,
                  (outlines[indexPath.row+1].destination?.page?.pageRef?.pageNumber ?? 0) >= currentPageNumber {
            cell.backgroundColor = .lightGray
        }
        
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
