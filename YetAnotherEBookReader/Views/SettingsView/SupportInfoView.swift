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
    @EnvironmentObject var container: AppContainer
    @StateObject private var viewModel = SupportInfoViewModel()

    var body: some View {
        List {
            Section {
                if let privacyHtml = viewModel.yabrPrivacyHtml {
                    NavigationLink {
                        WebViewUI(content: privacyHtml, baseURL: YabrAppInfo.shared.baseUrl)
                    } label: {
                        Text("Private Policy")
                    }
                }
                
                if let termsHtml = viewModel.yabrTermsHtml {
                    NavigationLink {
                        WebViewUI(content: termsHtml, baseURL: YabrAppInfo.shared.baseUrl)
                    } label: {
                        Text("Terms & Conditions")
                    }
                }
                
                if let yabrVersionHtml = viewModel.yabrVersionHtml {
                    NavigationLink {
                        WebViewUI(content: yabrVersionHtml, baseURL: YabrAppInfo.shared.baseUrl?.appendingPathComponent("releases"))
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
                    viewModel.showFolderPicker = true
                }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Export App Data")
                            Spacer()
                            if viewModel.isExporting {
                                ProgressView()
                            } else {
                                Image(systemName: "archivebox")
                            }
                        }
                        
                        if viewModel.isExporting {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: viewModel.exportProgress, total: 1.0)
                                    .progressViewStyle(LinearProgressViewStyle())
                                
                                Text(viewModel.currentExportFile)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                             }
                        }
                    }
                }
                .disabled(viewModel.isExporting)
            }
            
            Section {
                if let issueURL = YabrAppInfo.shared.newIssueUrl {
                    linkButtonBuilder(title: "Report an Issue", url: issueURL).padding()
                }
                if let enhancementURL = YabrAppInfo.shared.newEnhancementUrl {
                    linkButtonBuilder(title: "Suggestion & Request", url: enhancementURL).padding()
                }
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.onAppear()
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(
                title: Text("Export App Data"),
                message: Text(viewModel.alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $viewModel.showFolderPicker) {
            FolderPicker { folderURL in
                Task {
                    await viewModel.exportAppData(to: folderURL)
                }
            }
        }
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

struct SupportInfoView_Previews: PreviewProvider {
    static let container = AppContainer(mock: true)
    
    static var previews: some View {
        SupportInfoView()
            .environmentObject(container)
    }
}

struct FolderPicker: UIViewControllerRepresentable {
    var onFolderPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder, .directory])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: FolderPicker

        init(_ parent: FolderPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onFolderPicked(url)
        }
    }
}
