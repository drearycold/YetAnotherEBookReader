//
//  ReaderOptionsViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/13.
//

import Foundation
import SwiftUI

class ReaderOptionsViewModel: ObservableObject {
    let container: AppContainer
    let fontsManager: FontsManager
    
    // Help & Sheet presentation state
    @Published var optionsHelpFormat = false
    @Published var optionsHelpReader = false
    @Published var optionsHelpFont = false
    
    @Published var fontsFolderPresenting = false
    @Published var fontsFolderPicked = [URL]() {
        didSet {
            importFonts(from: fontsFolderPicked)
        }
    }
    @Published var fontsDetailPresenting = false
    @Published var fontsCount = 0
    @Published var fontsImportNotice = ""
    
    private var dismissAllTask: Task<Void, Never>?
    
    init(container: AppContainer, fontsManager: FontsManager) {
        self.container = container
        self.fontsManager = fontsManager
        
        setupBindings()
    }

    deinit {
        dismissAllTask?.cancel()
    }
    
    private func setupBindings() {
        dismissAllTask?.cancel()
        let dismissEvents = container.dismissAllEvents()
        dismissAllTask = Task { @MainActor [weak self] in
            for await _ in dismissEvents {
                guard !Task.isCancelled, let self else { return }
                self.fontsFolderPresenting = false
                self.fontsDetailPresenting = false
                self.optionsHelpFormat = false
                self.optionsHelpReader = false
                self.optionsHelpFont = false
            }
        }
    }
    
    // MARK: - Format / Reader Preference Bindings

    var preferredFormatBinding: Binding<Format> {
        Binding(
            get: { [weak self] in
                self?.container.sessionManager.getPreferredFormat() ?? .EPUB
            },
            set: { [weak self] in
                self?.container.sessionManager.updatePreferredFormat(for: $0)
            }
        )
    }

    func preferredReaderBinding(for format: Format) -> Binding<ReaderType> {
        Binding(
            get: { [weak self] in
                self?.container.sessionManager.getPreferredReader(for: format) ?? .YabrEPUB
            },
            set: { [weak self] in
                self?.container.sessionManager.updatePreferredReader(for: format, with: $0)
            }
        )
    }
    
    // MARK: - Custom Fonts Management
    
    func startImport() {
        fontsCount = fontsManager.userFontInfos.count
        fontsFolderPresenting = true
    }
    
    func startViewDetails() {
        fontsCount = fontsManager.userFontInfos.count
        fontsDetailPresenting = true
    }
    
    func handleDetailsDismiss() {
        fontsDetailPresenting = false
        let newCount = fontsManager.userFontInfos.count
        let deletedCount = fontsCount - newCount
        if deletedCount > 0 {
            fontsImportNotice = "Deleted \(deletedCount) font(s)"
        }
        fontsCount = newCount
    }
    
    func removeFontRows(at offsets: IndexSet) {
        fontsManager.removeCustomFonts(at: offsets)
        fontsManager.reloadCustomFonts()
    }
    
    private func importFonts(from tmpURLs: [URL]) {
        let urls = tmpURLs.filter { $0 != FontImportPicker.FakeURL }
        urls.forEach {
            print("documentPicker \($0.absoluteString)")
        }
        fontsImportNotice = ""
        guard let imported = fontsManager.importCustomFonts(urls: urls) else {
            fontsImportNotice = "Error occurred during import"
            return
        }
        fontsManager.reloadCustomFonts()
        let newCount = fontsManager.userFontInfos.count
        let deletedCount = fontsCount + imported.count - newCount
        if imported.count > 0 {
            fontsImportNotice = "Successfully imported \(imported.count) font(s)"
        }
        if deletedCount > 0 {
            if fontsImportNotice.count > 0 {
                fontsImportNotice = "\(fontsImportNotice), and deleted \(deletedCount) font(s)"
            } else {
                fontsImportNotice = "Deleted \(deletedCount) font(s)"
            }
        }
        if urls.count - imported.count > 0 {
            if fontsImportNotice.count > 0 {
                fontsImportNotice = "\(fontsImportNotice), and failed \(urls.count - imported.count) font(s)"
            } else {
                fontsImportNotice = "Failed \(urls.count - imported.count) font(s)"
            }
        }
        fontsCount = newCount
    }
}
