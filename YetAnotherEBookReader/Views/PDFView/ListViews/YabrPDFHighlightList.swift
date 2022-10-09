//
//  FolioReaderHighlightList.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 01/09/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit

class YabrPDFHighlightList: YabrPDFTableViewController {
    fileprivate var sections = [Int]()
    fileprivate var sectionHighlights = [Int: [PDFHighlight]]()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.register(YabrPDFHighlightListCell.self, forCellReuseIdentifier: kReuseCellIdentifier)
//        self.tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: kReuseHeaderFooterIdentifier)
        
        loadItems()
    }

    func loadItems() {
        guard let highlights = yabrPDFMetaSource?.yabrPDFHighlights(yabrPDFView)
        else { return }
        
        sectionHighlights = highlights.reduce(into: [:]) { partialResult, highlight in
            guard let highlightFirstPage = highlight.pos.first?.page else { return }
            let sectionKey = self.yabrPDFMetaSource?.yabrPDFOutline(yabrPDFView, for: highlightFirstPage)?.destination?.page?.pageRef?.pageNumber ?? highlightFirstPage
            
            if partialResult[sectionKey] != nil {
                partialResult[sectionKey]?.append(highlight)
                partialResult[sectionKey]?.sort(by: {
                    ($0.pos.first?.page ?? 0) < ($1.pos.first?.page ?? 0)
                })
            } else {
                partialResult[sectionKey] = [highlight]
            }
        }
        sections = sectionHighlights.keys.sorted()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        //TODO: Jump to the current chapter
        
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sectionHighlights[sections[section]]?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let yabrPDFView = yabrPDFView else { return nil }
        
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
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kReuseCellIdentifier, for: indexPath) as! YabrPDFHighlightListCell

        guard let yabrPDFView = yabrPDFView,
              let highlight = sectionHighlights[sections[indexPath.section]]?[indexPath.row] else {
            return cell
        }

        // Format date
        let dateString = dateFormatter.string(from: highlight.date)

        // Date
        cell.dateLabel.text = dateString.uppercased()
        cell.dateLabel.textColor = yabrPDFMetaSource?.yabrPDFOptionsIsNight(
            yabrPDFView,
            UIColor(white: 5, alpha: 0.3),
            UIColor.lightGray
        )
        
        // Text
        let text = NSMutableAttributedString(string: highlight.content)
        let range = NSRange(location: 0, length: text.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let textColor = yabrPDFMetaSource?.yabrPDFOptionsIsNight(
            yabrPDFView,
            UIColor.lightGray,
            UIColor.black
        ) ?? UIColor.darkText

        text.addAttribute(NSAttributedString.Key.paragraphStyle, value: paragraph, range: range)
        text.addAttribute(NSAttributedString.Key.font, value: UIFont(name: "Avenir-Light", size: 16)!, range: range)
        text.addAttribute(NSAttributedString.Key.foregroundColor, value: textColor, range: range)

        if (highlight.type == BookHighlightStyle.underline.rawValue) {
            text.addAttribute(NSAttributedString.Key.backgroundColor, value: UIColor.clear, range: range)
            text.addAttribute(NSAttributedString.Key.underlineColor, value: BookHighlightStyle.colorForStyle(highlight.type, nightMode: yabrPDFMetaSource?.yabrPDFOptionsIsNight(yabrPDFView, true, false) ?? false), range: range)
            text.addAttribute(NSAttributedString.Key.underlineStyle, value: NSNumber(value: NSUnderlineStyle.single.rawValue as Int), range: range)
        } else {
            text.addAttribute(NSAttributedString.Key.backgroundColor, value: BookHighlightStyle.colorForStyle(highlight.type, nightMode: yabrPDFMetaSource?.yabrPDFOptionsIsNight(yabrPDFView, true, false) ?? false), range: range)
        }

        // Text
        
        cell.highlightLabel.attributedText = text
        
        // Note text if it exists
        if let note = highlight.note {
            cell.noteLabel.text = note
        } else {
            cell.noteLabel.text = nil
        }

        
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let highlight = sectionHighlights[sections[indexPath.section]]?[indexPath.row] else {
            return 0.0
        }

        return 80 + (highlight.note != nil ? 40 : 0)
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let highlight = sectionHighlights[sections[indexPath.section]]?[indexPath.row]
        else { return }
        
//        yabrPDFMetaSource?.yabrPDFNavigate(yabrPDFView, pageNumber: highlight.page, offset: highlight.offset)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let highlight = sectionHighlights[sections[indexPath.section]]?[indexPath.row]
            else { return }

            //TODO: remove
            yabrPDFMetaSource?.yabrPDFHighlights(yabrPDFView, remove: highlight)
            
            sectionHighlights[sections[indexPath.section]]?.remove(at: indexPath.row)
            if sectionHighlights[sections[indexPath.section]]?.isEmpty == true, sections.count > 1 {
                sectionHighlights.removeValue(forKey: sections[indexPath.section])
                sections.remove(at: indexPath.section)
            }
            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }
    
    
    // MARK: - Handle rotation transition
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        tableView.reloadData()
    }
    
}
