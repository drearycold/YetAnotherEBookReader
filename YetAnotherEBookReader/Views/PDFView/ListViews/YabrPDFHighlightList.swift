//
//  FolioReaderHighlightList.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 01/09/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
class YabrPDFHighlightList: YabrPDFTableViewController {
    fileprivate var sectionHighlights = [Int: [PDFHighlight]]()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.register(YabrPDFHighlightListCell.self, forCellReuseIdentifier: kReuseCellIdentifier)
        
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

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sectionHighlights[sections[section]]?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kReuseCellIdentifier, for: indexPath) as! YabrPDFHighlightListCell

        guard let highlight = sectionHighlights[sections[indexPath.section]]?[indexPath.row] else {
            return cell
        }

        cell.configure(
            highlight: highlight,
            date: dateFormatter.string(from: highlight.date).uppercased(),
            style: listStyle
        )
        return cell
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let highlight = sectionHighlights[sections[indexPath.section]]?[indexPath.row],
              let page = highlight.pos.first?.page,
              let pdfPage = yabrPDFView?.document?.page(at: page - 1)
        else { return }
        
        // The step showing its first line, on a page read in steps (#97).
        if let pdfViewController,
           let rect = pdfViewController.surface.highlights[highlight.uuid]?.first?.selection.bounds(for: pdfPage) {
            pdfViewController.jump(to: pdfPage, showing: rect)
        } else {
            yabrPDFView?.go(to: pdfPage)
        }
        self.dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let highlight = sectionHighlights[sections[indexPath.section]]?[indexPath.row]
        else { return nil }

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.removeHighlight(highlight, at: indexPath)
            completion(true)
        }
        let note = UIContextualAction(style: .normal, title: highlight.note == nil ? "Note" : "Edit Note") { [weak self] _, _, completion in
            self?.editNote(of: highlight)
            completion(true)
        }
        note.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [delete, note])
    }

    /// Removes through the annotation manager so the page and the persisted
    /// highlights stay in step.
    private func removeHighlight(_ highlight: PDFHighlight, at indexPath: IndexPath) {
        pdfViewController?.annotationManager.removeHighlight(uuid: highlight.uuid)

        guard tableView.window != nil else { return }
        sectionHighlights[sections[indexPath.section]]?.remove(at: indexPath.row)
        if sectionHighlights[sections[indexPath.section]]?.isEmpty == true, sections.count > 1 {
            sectionHighlights.removeValue(forKey: sections[indexPath.section])
            sections.remove(at: indexPath.section)
            tableView.deleteSections(IndexSet(integer: indexPath.section), with: .fade)
        } else {
            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }

    private func editNote(of highlight: PDFHighlight) {
        guard let pdfViewController else { return }
        pdfViewController.presentNoteEditor(for: highlight.uuid, from: self) { [weak self] in
            self?.loadItems()
            self?.tableView.reloadData()
        }
    }
    
    
    // MARK: - Handle rotation transition
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        tableView.reloadData()
    }
    
}
