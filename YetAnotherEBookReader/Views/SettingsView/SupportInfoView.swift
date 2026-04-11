//
//  SupportInfoView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/17.
//

import SwiftUI
import ReadiumZIPFoundation

#if canImport(UserMessagingPlatform)
import UserMessagingPlatform
#endif

struct SupportInfoView: View {
    @Environment(\.openURL) var openURL
    @EnvironmentObject var modelData: ModelData

    @State private var privacyWebViewPresenting = false
    @State private var termsWebViewPresenting = false
    
    @State private var yabrPrivacyHtml: String?
    @State private var yabrTermsHtml: String?
    @State private var yabrVersionHtml: String?
    
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    
    @State private var exportProgress: Double = 0
    @State private var currentExportFile = ""
    
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    var body: some View {
        List {
            Section {
                
                if let privacyHtml = modelData.yabrPrivacyHtml {
                    NavigationLink {
                        WebViewUI(content: privacyHtml, baseURL: modelData.yabrBaseUrl)
                    } label: {
                        Text("Private Policy")
                    }
                }
                
                if let termsHtml = modelData.yabrTermsHtml {
                    NavigationLink {
                        WebViewUI(content: termsHtml, baseURL: modelData.yabrBaseUrl)
                    } label: {
                        Text("Terms & Conditions")
                    }
                }
                
                if let yabrVersionHtml = self.yabrVersionHtml {
                    NavigationLink {
                        WebViewUI(content: yabrVersionHtml, baseURL: modelData.yabrBaseUrl?.appendingPathComponent("releases"))
                    } label: {
                        Text("Version History")
                    }
                }
                
#if canImport(UserMessagingPlatform)
                NavigationLink {
                    List {
                        HStack {
                            Text("Status")
                            Spacer()
                            Text("\(UMPConsentInformation.sharedInstance.consentStatus.rawValue)")
                            Text("/")
                            Text("\(UMPConsentInformation.sharedInstance.formStatus.rawValue)")
                        }
                        Button {
                            UMPConsentInformation.sharedInstance.reset()
                        } label: {
                            Text("Reset Tracking Consent")
                        }.disabled(UMPConsentInformation.sharedInstance.consentStatus != UMPConsentStatus.obtained)
                    }
                } label: {
                    Text("Reset Tracking Consent")
                }
#endif
            }
            
            Section(header: Text("Data Management")) {
                Button(action: {
                    Task {
                        await exportAppData()
                    }
                }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Export App Data")
                            Spacer()
                            if isExporting {
                                ProgressView()
                            } else {
                                Image(systemName: "archivebox")
                            }
                        }
                        
                        if isExporting {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: exportProgress, total: 1.0)
                                    .progressViewStyle(LinearProgressViewStyle())
                                
                                Text(currentExportFile)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .disabled(isExporting)
            }
            
            Section {
                if let issueURL = modelData.yabrNewIssueUrl {
                    linkButtonBuilder(title: "Report an Issue", url: issueURL).padding()
                }
                if let enhancementURL = modelData.yabrNewEnhancementUrl {
                    linkButtonBuilder(title: "Suggestion & Request", url: enhancementURL).padding()
                }
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            self.yabrPrivacyHtml = modelData.yabrPrivacyHtml
            self.yabrTermsHtml = modelData.yabrTermsHtml
            self.yabrVersionHtml = modelData.yabrVersionHtml
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Export App Data"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"), action: {
                    if exportURL != nil {
                        showShareSheet = true
                    }
                })
            )
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            if let url = exportURL {
                try? FileManager.default.removeItem(at: url)
                exportURL = nil
            }
        }) {
            if let url = exportURL {
                DocumentPicker(url: url)
            }
        }
    }
    
    private func exportAppData() async {
        isExporting = true
        exportProgress = 0
        currentExportFile = "Preparing..."
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        
        let zipFileName = "YABR_Backup_\(Int(Date().timeIntervalSince1970)).zip"
        let destinationURL = tempDir.appendingPathComponent(zipFileName)
        
        do {
            // Run zipping in a detached task to keep the main thread free
            let result = try await Task.detached(priority: .userInitiated) {
                return try await self.performZip(destinationURL: destinationURL)
            }.value
            
            await MainActor.run {
                self.currentExportFile = "Finalizing..."
                self.exportProgress = 1.0
                self.exportURL = result.url
                self.isExporting = false
                
                if result.skipped > 0 {
                    self.alertMessage = "Export completed with \(result.success) files. \(result.skipped) files were skipped due to system restrictions."
                    self.showAlert = true
                } else {
                    self.showShareSheet = true
                }
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            await MainActor.run {
                self.isExporting = false
                self.alertMessage = "Export failed: \(error.localizedDescription)"
                self.showAlert = true
            }
        }
    }
    
    // Helper function to ensure Archive is released immediately after use
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
                                throw NSError(domain: "YABRError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Read failed at \(position)"])
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
    
    @ViewBuilder
    private func linkButtonBuilder(title: String, url: String) -> some View {
        Button(action:{
            openURL(URL(string: url)!)
        }) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "square.and.arrow.up")
            }
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

struct SupportInfoView_Previews: PreviewProvider {
    static let modelData = ModelData(mock: true)
    static var previews: some View {
        SupportInfoView().environmentObject(modelData)
    }
}
