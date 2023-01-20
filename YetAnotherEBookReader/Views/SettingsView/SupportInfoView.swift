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
}

struct SupportInfoView_Previews: PreviewProvider {
    static let modelData = ModelData(mock: true)
    
    static var previews: some View {
        SupportInfoView()
            .environmentObject(modelData)
    }
}
