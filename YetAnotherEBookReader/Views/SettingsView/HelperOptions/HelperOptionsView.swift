//
//  HelperOptionsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/12/31.
//

import SwiftUI
import Combine

struct HelperOptionsView: View {
    @EnvironmentObject var modelData: ModelData

    @State private var customDictViewerEnabled = false
    @State private var customDictViewerURL = ""
    @State private var customDictViewerURLStored: URL?
    @State private var customDictViewerURLMalformed = false
    @State private var customDictViewerInfoPresenting = false
    @State private var customDictViewerTestPresenting = false
    
    @State private var dismissAllCancellable: AnyCancellable?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Custom Dictionary Viewer", isOn: $customDictViewerEnabled)
                    .onChange(of: customDictViewerEnabled, perform: { value in
                        _ = modelData.updateCustomDictViewer(enabled: value, value: nil)
                    })
                    .font(.title3)

                HStack {
                    Text("Experimental!!! Instructions on the road")
                        .font(.caption)
                    Spacer()
                    Button(action:{ customDictViewerInfoPresenting = true}) {
                        Text("How to setup?")
                            .font(.caption)
                        Image(systemName: "questionmark.circle")
                    }
                    .sheet(isPresented: $customDictViewerInfoPresenting, onDismiss: { customDictViewerInfoPresenting = false } ) {
                        WebViewUI(content: """
                            <html>
                            <head>
                                <meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no'>
                            </head>
                            <body>
                                <h1>How to setup flask-mdict</h1>
                                <div>
                                <p>
                                Please refer to <a href="https://github.com/liuyug/flask-mdict">https://github.com/liuyug/flask-mdict</a> for instructions.
                                </p>
                                <p>
                                Then fill server address to "URL" field.
                                </p>
                                <div>
                            </body>
                            </html>
                            """, baseURL: nil)
                    }
                }
                
                Text("If you are not satisfied with Apple's build-in dictionaries, we can make use of a private dictionary server powered by flask-mdict. Limited to \(ReaderType.YabrEPUB.rawValue) and \(ReaderType.YabrPDF.rawValue).")
                    .multilineTextAlignment(.leading)
                    .font(.caption)
                
                HStack {
                    Text("URL:")
                    TextField("", text: $customDictViewerURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .border(Color(UIColor.separator))
                    .onChange(of: customDictViewerURL, perform: { value in
                        customDictViewerURLMalformed = checkCustomDictViewerURL(value: value)
                    })
                    
                    Text("?word=hello")
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Spacer()
                    if customDictViewerURL.isEmpty {
                        Text("")
                    }
                    else if customDictViewerEnabled && customDictViewerURLMalformed {
                        Text("URL Malformed").font(.caption).foregroundColor(.red)
                    }
                    Button(action:{
                        customDictViewerTestPresenting = true
                    }) {
                        Text("Preview")
                    }.disabled(customDictViewerURLMalformed)
                    .sheet(isPresented: $customDictViewerTestPresenting, onDismiss: { customDictViewerTestPresenting = false }) {
                        MDictViewUIVC(server: URL(string: customDictViewerURL)!)
                    }
                    
                    Button(action:{
                        customDictViewerURLStored = modelData.updateCustomDictViewer(enabled: customDictViewerEnabled, value: customDictViewerURL)
                    }) {
                        Text("Update")
                    }.disabled(customDictViewerURLMalformed || URL(string: customDictViewerURL) == customDictViewerURLStored)
                    
                    Button(action:{
                        customDictViewerURL = customDictViewerURLStored?.absoluteString ?? ""
                    }) {
                        Text("Restore")
                    }.disabled(URL(string: customDictViewerURL) == customDictViewerURLStored)
                }.disabled(!customDictViewerEnabled)
            }.padding()
        }
        .onAppear() {
            dismissAllCancellable?.cancel()
            dismissAllCancellable = modelData.dismissAllPublisher.sink { _ in
                customDictViewerInfoPresenting = false
                customDictViewerTestPresenting = false
            }
            
            (customDictViewerEnabled, customDictViewerURLStored) = modelData.getCustomDictViewer()
            customDictViewerURL = customDictViewerURLStored?.absoluteString ?? ""
            customDictViewerURLMalformed = checkCustomDictViewerURL(value: customDictViewerURL)
        }.frame(maxWidth: 720)
    }
    
    private func checkCustomDictViewerURL(value: String) -> Bool {
        guard let url = URL(string: value) else {
            return true
        }
        guard url.scheme == "http" || url.scheme == "https" else {
            return true
        }
        return false
    }
    
}

struct HelperOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        HelperOptionsView()
    }
}
