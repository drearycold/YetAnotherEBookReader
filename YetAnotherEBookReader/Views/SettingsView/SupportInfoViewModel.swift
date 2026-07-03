//
//  SupportInfoViewModel.swift
//  YetAnotherEBookReader
//
//  Created by opencode on 2026-06-18.
//

import SwiftUI
import ReadiumZIPFoundation

@available(macCatalyst 14.0, *)
final class SupportInfoViewModel: ObservableObject {
    @Published var yabrPrivacyHtml: String?
    @Published var yabrTermsHtml: String?
    @Published var yabrVersionHtml: String?

    @Published var isExporting = false
    @Published var showFolderPicker = false
    @Published var exportProgress: Double = 0
    @Published var currentExportFile = ""
    @Published var alertMessage = ""
    @Published var showAlert = false

    init() {
        yabrPrivacyHtml = YabrAppInfo.shared.privacyHtml
        yabrTermsHtml = YabrAppInfo.shared.termsHtml
        yabrVersionHtml = YabrAppInfo.shared.versionHtml
    }

    func onAppear() {
        yabrPrivacyHtml = YabrAppInfo.shared.privacyHtml
        yabrTermsHtml = YabrAppInfo.shared.termsHtml
        yabrVersionHtml = YabrAppInfo.shared.versionHtml
    }

    func exportAppData(to folderURL: URL) async {
        guard folderURL.startAccessingSecurityScopedResource() else {
            await MainActor.run {
                self.alertMessage = "Access to the selected folder was denied."
                self.showAlert = true
            }
            return
        }

        defer { folderURL.stopAccessingSecurityScopedResource() }

        await MainActor.run {
            isExporting = true
            exportProgress = 0
            currentExportFile = "Preparing..."
        }

        let zipFileName = "YABR_Backup_\(Int(Date().timeIntervalSince1970)).zip"
        let destinationURL = folderURL.appendingPathComponent(zipFileName)

        do {
            let result = try await Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { throw SupportInfoError.viewModelDeinitialized }
                return try await self.performZip(destinationURL: destinationURL)
            }.value

            await MainActor.run {
                self.currentExportFile = "Completed"
                self.exportProgress = 1.0
                self.isExporting = false

                if result.skipped > 0 {
                    self.alertMessage = "Export saved to: \(zipFileName)\n\n\(result.success) files added. \(result.skipped) files were skipped due to system restrictions."
                } else {
                    self.alertMessage = "Success! Backup saved as \(zipFileName)."
                }
                self.showAlert = true
            }
        } catch {
            await MainActor.run {
                self.isExporting = false
                self.alertMessage = "Export failed: \(error.localizedDescription)"
                self.showAlert = true
            }
        }
    }

    private func performZip(destinationURL: URL) async throws -> (url: URL, skipped: Int, success: Int) {
        let fileManager = FileManager.default
        let archive = try await Archive(url: destinationURL, accessMode: .create)

        let docsDir = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).resolvingSymlinksInPath()
        let appSupportDir = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).resolvingSymlinksInPath()

        let sources = [
            (url: docsDir, label: "Documents"),
            (url: appSupportDir, label: "ApplicationSupport")
        ]

        var totalFiles = 0
        for source in sources {
            let enumerator = fileManager.enumerator(at: source.url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while enumerator?.nextObject() != nil { totalFiles += 1 }
        }

        var processedFiles = 0
        var successCount = 0
        var skippedCount = 0

        for source in sources {
            let enumerator = fileManager.enumerator(at: source.url, includingPropertiesForKeys: [.isDirectoryKey, .fileResourceTypeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])

            while let sourceURL = (enumerator?.nextObject() as? URL)?.resolvingSymlinksInPath() {
                if sourceURL.path == destinationURL.path { continue }

                let relativePath = sourceURL.path.hasPrefix(source.url.path) ? String(sourceURL.path.dropFirst(source.url.path.count)) : sourceURL.path
                let entryPath = source.label + relativePath

                processedFiles += 1
                if processedFiles % 5 == 0 || processedFiles == totalFiles {
                    let fileName = sourceURL.lastPathComponent
                    let progress = Double(processedFiles) / Double(max(1, totalFiles))
                    await MainActor.run {
                        self.currentExportFile = "Adding \(fileName)..."
                        self.exportProgress = progress
                    }
                }

                do {
                    let resourceValues = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .fileResourceTypeKey])
                    if resourceValues.fileResourceType == .directory {
                        try await archive.addEntry(with: entryPath + "/", type: .directory, uncompressedSize: 0, provider: { _, _ in return Data() })
                    } else if resourceValues.fileResourceType == .regular {
                        let fileHandle = try FileHandle(forReadingFrom: sourceURL)
                        defer { try? fileHandle.close() }

                        let fileSize = try fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64 ?? 0

                        try await archive.addEntry(with: entryPath, type: .file, uncompressedSize: fileSize, provider: { (position, size) -> Data in
                            try fileHandle.seek(toOffset: UInt64(position))
                            guard let data = try fileHandle.read(upToCount: size) else {
                                throw SupportInfoError.fileReadFailed(position: position, size: size, path: sourceURL.lastPathComponent)
                            }
                            return data
                        })
                        successCount += 1
                    } else {
                        skippedCount += 1
                    }
                } catch {
                    skippedCount += 1
                }
            }
        }

        return (destinationURL, skippedCount, successCount)
    }
}

enum SupportInfoError: LocalizedError {
    case viewModelDeinitialized
    case fileReadFailed(position: Int64, size: Int, path: String)

    var errorDescription: String? {
        switch self {
        case .viewModelDeinitialized:
            return "Backup failed: View model was deinitialized."
        case .fileReadFailed(let position, let size, let path):
            return "Read failed at position \(position) (size: \(size)) for file: \(path)"
        }
    }
}
