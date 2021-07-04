//
//  ReaderOptionsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/13.
//

import SwiftUI

struct ReaderOptionsView: View {
    @EnvironmentObject var modelData: ModelData
    
    @State private var folioReaderEnabled = true
    @State private var folioReaderInfoPresenting = false
    
    @State private var readiumEpubEnabled = true
    @State private var readiumEpubInfoPresenting = false
    
    @State private var customDictViewerEnabled = false
    @State private var customDictViewerURL = ""
    @State private var customDictViewerInfoPresenting = false
    
    var body: some View {
        ScrollView {
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Enable FolioReader for EPUB", isOn: $folioReaderEnabled)
                    Button(action:{
                        folioReaderInfoPresenting = true
                    }) {
                        Image(systemName: "questionmark.circle")
                    }
                }
                Text("Default Options")
            }
            .padding()
            .sheet(isPresented: $folioReaderInfoPresenting, onDismiss: { folioReaderInfoPresenting = false } ) {
                WebViewUI(content: "<html><body><h1>Hello World</h1></body></html>", baseURL: nil)
            }.hidden()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Enable Readium for EPUB", isOn: $readiumEpubEnabled)
                    Button(action:{
                        readiumEpubInfoPresenting = true
                    }) {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .padding()
            .sheet(isPresented: $readiumEpubInfoPresenting, onDismiss: { readiumEpubInfoPresenting = false } ) {
                WebViewUI(content: "<html><body><h1>Hello World Readium</h1></body></html>", baseURL: nil)
            }.hidden()
            
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Enable Custom Dictionary Viewer", isOn: $customDictViewerEnabled)

                Text("Experimental!!!\nIf you are not satisfied with Apple's build-in dictionaries, we can make use of a private dictionary server powered by flask-mdict.\nLimited to FolioReader and YabrPDFView.")
                    .font(.caption)
                
                HStack {
                    Text("URL:")
                    TextField("", text: $customDictViewerURL, onCommit: {
                        modelData.updateCustomDictViewer(enabled: customDictViewerEnabled, value: customDictViewerURL)
                    })
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .border(Color(UIColor.separator))
                }.disabled(!customDictViewerEnabled)
                
                HStack {
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
                
            }.onChange(of: customDictViewerEnabled) { value in
                modelData.updateCustomDictViewer(enabled: customDictViewerEnabled, value: customDictViewerURL)
            }.padding()
            
            Spacer()
        }   //ScrollView
        
    }
}

struct ReaderOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderOptionsView().environmentObject(ModelData())
    }
}
