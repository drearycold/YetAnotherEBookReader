//
//  ReaderOptionsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/13.
//

import SwiftUI

struct ReaderOptionsView: View {
    @EnvironmentObject var modelData: ModelData
    
    @State private var optionsFormatPresenting = false
    @State private var optionsReaderEpubPresenting = false
    @State private var optionsReaderPdfPresenting = false
    @State private var optionsReaderCbzPresenting = false

    @State private var customDictViewerEnabled = false
    @State private var customDictViewerURL = ""
    @State private var customDictViewerURLStored: URL?
    @State private var customDictViewerURLMalformed = false
    @State private var customDictViewerInfoPresenting = false
    @State private var customDictViewerTestPresenting = false
    
    var body: some View {
        ScrollView {
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Preferred Book Format and Reader")
                    .font(.title3)
                
                Text("Book Format")
                    .frame(minWidth: 160, alignment: .leading)
                    .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                HStack {
                    Spacer()
                    Picker("PreferredFormat", selection: preferredReaderTypeBinding()) {
                        ForEach(Format.allCases.dropFirst(), id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }.pickerStyle(SegmentedPickerStyle())
                    .frame(maxWidth: 600)
                    
                    Button(action:{
                        optionsFormatPresenting = true
                    }) {
                        Image(systemName: "questionmark.circle")
                    }
                    Spacer()
                }.sheet(isPresented: $optionsFormatPresenting, onDismiss: { optionsFormatPresenting = false}, content: {
                    FormatOptionsView()
                })
                
                ForEach(Format.allCases.dropFirst(), id: \.self) { format in
                    HStack {
                        Text("Reader for \(format.rawValue)")
                        .frame(minWidth: 160, alignment: .leading)
                        .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                        Spacer()
                    }
                    
                    HStack {
                        Spacer()
                        Picker("Prefered", selection: preferredReaderTypeBinding(for: format)) {
                            ForEach(modelData.formatReaderMap[format]!, id: \.self) { reader in
                                Text(reader.rawValue).tag(reader)
                            }
                        }.pickerStyle(SegmentedPickerStyle())
                        .frame(maxWidth: 600)
                        
                        Button(action:{
                            switch(format) {
                            case .EPUB:
                                optionsReaderEpubPresenting = true
                            case .PDF:
                                optionsReaderPdfPresenting = true
                            case .CBZ:
                                optionsReaderCbzPresenting = true
                            default: break
                            }
                        }) {
                            Image(systemName: "questionmark.circle")
                        }
                        Spacer()
                    }
                }.sheet(isPresented: $optionsReaderEpubPresenting, onDismiss: { optionsReaderEpubPresenting = false }, content: {
                        ReaderOptionsEpubView()
                    
                })
                .sheet(isPresented: $optionsReaderPdfPresenting, onDismiss: { optionsReaderPdfPresenting = false }, content: {
                        ReaderOptionsPdfView()
                })
                .sheet(isPresented: $optionsReaderCbzPresenting, onDismiss: { optionsReaderCbzPresenting = false }, content: {
                        ReaderOptionsCbzView()
                })
            }.padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Custom Dictionary Viewer", isOn: $customDictViewerEnabled)
                    .onChange(of: customDictViewerEnabled, perform: { value in
                        _ = modelData.updateCustomDictViewer(enabled: value, value: nil)
                    })
                    .font(.title3)

                HStack {
                    Text("Experimental!!!")
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
            
            Divider()
            
            Spacer()
        }   //ScrollView
        .onAppear() {
            (customDictViewerEnabled, customDictViewerURLStored) = modelData.getCustomDictViewer()
            customDictViewerURL = customDictViewerURLStored?.absoluteString ?? ""
            customDictViewerURLMalformed = checkCustomDictViewerURL(value: customDictViewerURL)
        }
    }
    
    private func preferredReaderTypeBinding(for format: Format) -> Binding<ReaderType> {
        return .init(
            get: {
                modelData.getPreferredReader(for: format)
            },
            set: {
                modelData.updatePreferredReader(for: format, with: $0)
            })
    }
    
    private func preferredReaderTypeBinding() -> Binding<Format>{
        return .init(
            get: {
                return modelData.getPreferredFormat()
            },
            set: {
                modelData.updatePreferredFormat(for: $0)
            }
        )
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

struct ReaderOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderOptionsView().environmentObject(ModelData())
    }
}
