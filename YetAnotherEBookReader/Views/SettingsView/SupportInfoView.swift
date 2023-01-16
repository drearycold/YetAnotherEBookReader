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
    
    var body: some View {
        List {
#if canImport(UserMessagingPlatform)
                Button(action: { UMPConsentInformation.sharedInstance.reset() }) {
                    Text("Reset Tracking Consent")
                }.padding()
#endif
            
            if let privacyHtml = modelData.yabrPrivacyHtml {
                Button(action: { privacyWebViewPresenting = true }) {
                    Text("Private Policy")
                }.sheet(isPresented: $privacyWebViewPresenting) {
                    SupportInfoView.privacyWebView(content: privacyHtml)
                }.padding()
            }
            
            if let termsHtml = modelData.yabrTermsHtml {
                Button(action: { termsWebViewPresenting = true }) {
                    Text("Terms & Conditions")
                }.sheet(isPresented: $termsWebViewPresenting) {
                    SupportInfoView.termsWebView(content: termsHtml)
                }.padding()
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
