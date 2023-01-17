//
//  SupportInfoView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/17.
//

import SwiftUI

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
    
    var body: some View {
        List {
            Section {
                
                if let privacyHtml = modelData.yabrPrivacyHtml {
                    NavigationLink {
                        SupportInfoView.privacyWebView(content: privacyHtml)
                    } label: {
                        Text("Private Policy")
                    }
                }
                
                if let termsHtml = modelData.yabrTermsHtml {
                    NavigationLink {
                        SupportInfoView.termsWebView(content: termsHtml)
                    } label: {
                        Text("Terms & Conditions")
                    }
                }
                
                if let yabrVersionHtml = self.yabrVersionHtml {
                    NavigationLink {
                        WebViewUI(content: yabrVersionHtml, baseURL: URL(string:"https://github.com/drearycold/YetAnotherEBookReader/releases"))
                    } label: {
                        Text("Version History")
                    }
                }
                
#if canImport(UserMessagingPlatform)
                NavigationLink {
                    VStack {
                        Button {
                            UMPConsentInformation.sharedInstance.reset()
                        } label: {
                            Text("Reset")
                        }
                    }
                } label: {
                    Text("Reset Tracking Consent")
                }
#endif
            }
            
            if let issueURL = modelData.yabrNewIssueUrl {
                linkButtonBuilder(title: "Report an Issue", url: issueURL).padding()
            }
            if let enhancementURL = modelData.yabrNewEnhancementUrl {
                linkButtonBuilder(title: "Suggestion & Request", url: enhancementURL).padding()
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            self.yabrPrivacyHtml = modelData.yabrPrivacyHtml
            self.yabrTermsHtml = modelData.yabrTermsHtml
            self.yabrVersionHtml = modelData.yabrVersionHtml
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
    
    @ViewBuilder
    static func privacyWebView(content: String) -> some View {
        WebViewUI(content: content, baseURL: URL(string:"https://github.com/drearycold/YetAnotherEBookReader/blob/local_library_support/Privacy.md"))
    }
    
    @ViewBuilder
    static func termsWebView(content: String) -> some View {
        WebViewUI(content: content, baseURL: URL(string: "https://github.com/drearycold/YetAnotherEBookReader/blob/local_library_support/Terms.md"))
    }
}

struct SupportInfoView_Previews: PreviewProvider {
    static let modelData = ModelData(mock: true)
    
    static var previews: some View {
        SupportInfoView()
            .environmentObject(modelData)
    }
}
