//
//  ReaderOptionsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/13.
//

import SwiftUI

struct ReaderOptionsView: View {
    @EnvironmentObject var modelData: ModelData
    
    @State private var customDictViewerEnabled = false
    @State private var customDictViewerURL = ""
    @State private var customDictViewerMalformed = false
    @State private var customDictViewerInfoPresenting = false
    @State private var customDictViewerTestPresenting = false

    
    var body: some View {
        ScrollView {
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Preferred Book Format and Reader")
                
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
                        
                    }) {
                        Image(systemName: "gearshape")
                    }
                    
                    Button(action:{
                        
                    }) {
                        Image(systemName: "questionmark.circle")
                    }
                    Spacer()
                }
                
                ForEach(Format.allCases.dropFirst(), id: \.self) { format in
                    Text("Reader for \(format.rawValue)")
                        .frame(minWidth: 160, alignment: .leading)
                        .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                    
                    HStack {
                        Spacer()
                        Picker("Prefered", selection: preferredReaderTypeBinding(for: format)) {
                            ForEach(modelData.formatReaderMap[format]!, id: \.self) { reader in
                                Text(reader.rawValue).tag(reader)
                            }
                        }.pickerStyle(SegmentedPickerStyle())
                        .frame(maxWidth: 600)
                        
                        Button(action:{
                            
                        }) {
                            Image(systemName: "gearshape")
                        }
                        
                        Button(action:{
                            
                        }) {
                            Image(systemName: "questionmark.circle")
                        }
                        Spacer()
                    }
                }
            }.padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Enable Custom Dictionary Viewer", isOn: $customDictViewerEnabled)

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
                
                Text("If you are not satisfied with Apple's build-in dictionaries, we can make use of a private dictionary server powered by flask-mdict.\nLimited to FolioReader and YabrPDFView.")
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
                    Text("?word=hello")
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Spacer()
                    Button(action:{
                        guard URL(string: customDictViewerURL) != nil else {
                            customDictViewerMalformed = true
                            return
                        }
                        customDictViewerTestPresenting = true
                        
                    }) {
                        Text("Test")
                    }.disabled(customDictViewerURL.isEmpty)
                    .sheet(isPresented: $customDictViewerTestPresenting, onDismiss: { customDictViewerTestPresenting = false }) {
                        MDictViewUIVC(server: URL(string: customDictViewerURL)!)
                    }
                    .alert(isPresented: $customDictViewerMalformed, content: {
                        Alert(title: Text("Error"), message: Text("URL Malformed"), dismissButton: .cancel())
                    })
                    
                    Button(action:{
                        guard URL(string: customDictViewerURL) != nil else {
                            customDictViewerMalformed = true
                            return
                        }
                        modelData.updateCustomDictViewer(enabled: customDictViewerEnabled, value: customDictViewerURL)
                    }) {
                        Text("Update")
                    }.disabled(customDictViewerURL.isEmpty || customDictViewerURL == (modelData.getCustomDictViewer()?.absoluteString ?? ""))
                    
                    Button(action:{
                        customDictViewerURL = modelData.getCustomDictViewer()?.absoluteString ?? ""
                    }) {
                        Text("Restore")
                    }.disabled(customDictViewerURL == (modelData.getCustomDictViewer()?.absoluteString ?? ""))
                }.disabled(!customDictViewerEnabled)
                
                
                
            }.padding()
            
            Divider()
            
            Spacer()
        }   //ScrollView
        .onAppear() {
            customDictViewerURL = modelData.getCustomDictViewer()?.absoluteString ?? ""
            customDictViewerEnabled = !customDictViewerURL.isEmpty
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
}

struct ReaderOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderOptionsView().environmentObject(ModelData())
    }
}
