//
//  ReaderOptionsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/13.
//

import SwiftUI
import Combine

struct ReaderOptionsView: View {
    @EnvironmentObject var modelData: ModelData
    
    @State private var optionsFormatPresenting = false
    @State private var optionsReaderEpubPresenting = false
    @State private var optionsReaderPdfPresenting = false
    @State private var optionsReaderCbzPresenting = false

    @State private var fontsFolderPresenting = false
    @State private var fontsFolderPicked = [URL]()
    @State private var fontsDetailPresenting = false
    @State private var fontsCount = 0
    @State private var fontsImportNotice = ""
    
    @State private var customDictViewerEnabled = false
    @State private var customDictViewerURL = ""
    @State private var customDictViewerURLStored: URL?
    @State private var customDictViewerURLMalformed = false
    @State private var customDictViewerInfoPresenting = false
    @State private var customDictViewerTestPresenting = false
    
    @State private var updater = 0
    
    @State private var dismissAllCancellable: AnyCancellable?
    
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
                Text("Custom Fonts for \(ReaderType.YabrEPUB.rawValue)")
                    .font(.title3)
                Group {
                    Text("Don't get limited by eBook publisher's aesthetic. \(ReaderType.YabrEPUB.rawValue) supports substituting eBook content fonts with your favorite choosing.")
                    Text("You can place font files inside \"Fonts\" folder of this App or import them directly from here. They will appear in the \"Font\" tab of \(ReaderType.YabrEPUB.rawValue)'s style menu.")
                    Text("Currently supports TrueType (.ttf) and OpenType (.otf).")
                }.font(.caption)
                HStack {
                    Text("Loaded \(modelData.userFontInfos.count) font(s)")
                    Spacer()
                    
                    Button(action:{
                        fontsCount = modelData.userFontInfos.count
                        fontsFolderPresenting = true
                    }) {
                        Text("Import")
                    }
                    
                    Button(action:{
                        fontsCount = modelData.userFontInfos.count
                        fontsDetailPresenting = true
                    }) {
                        Text("View")
                            .disabled(modelData.userFontInfos.isEmpty)
                    }
                }
                HStack {
                    Text(fontsImportNotice).font(.caption)
                }
            }
            .sheet(isPresented: $fontsDetailPresenting, onDismiss: {
                fontsDetailPresenting = false
                let newCount = modelData.userFontInfos.count
                let deletedCount = fontsCount - newCount
                if deletedCount > 0 {
                    fontsImportNotice = "Deleted \(deletedCount) font(s)"
                }
                fontsCount = newCount
            }) {
                NavigationView {
                    List {
                        ForEach(
                            modelData.userFontInfos.sorted {
                                    ( $0.value.displayName ?? $0.key) < ( $1.value.displayName ?? $1.key)
                                } , id: \.key ) { (fontId, fontInfo) in
                            NavigationLink(destination: FontPreviewBuilder(fontId: fontId, fontInfo: fontInfo)) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(fontInfo.localizedName ?? fontInfo.displayName ?? fontId)
                                        .font(Font.custom(fontId, size: 20, relativeTo: .body))
                                    HStack {
                                        Spacer()
                                        Text(fontInfo.fileURL?.lastPathComponent ?? "").font(.caption2)
                                    }
                                }
                            }
                        }.onDelete(perform: removeFontRows)
                    }.navigationTitle("Favorite Fonts")
                }
            }
            .sheet(isPresented: $fontsFolderPresenting, onDismiss: {
                fontsFolderPresenting = false
            }) {
                FontImportPicker(fontURLs: $fontsFolderPicked)
            }
            .onChange(of: fontsFolderPicked) { tmpURLs in
                let urls = tmpURLs.filter { $0 != FontImportPicker.FakeURL }
                urls.forEach {
                    print("documentPicker \($0.absoluteString)")
                }
                fontsImportNotice = ""
                guard let imported = modelData.importCustomFonts(urls: urls) else {
                    fontsImportNotice = "Error occured during import"
                    return
                }
                modelData.reloadCustomFonts()
                let newCount = modelData.userFontInfos.count
                let deletedCount = fontsCount + imported.count - newCount
                if imported.count > 0 {
                    fontsImportNotice = "Successfully imported \(imported.count) font(s)"
                }
                if deletedCount > 0 {
                    if fontsImportNotice.count > 0 {
                        fontsImportNotice = "\(fontsImportNotice), and deleted \(deletedCount) font(s)"
                    } else {
                        fontsImportNotice = "Deleted \(deletedCount) font(s)"
                    }
                }
                if urls.count - imported.count > 0 {
                    if fontsImportNotice.count > 0 {
                        fontsImportNotice = "\(fontsImportNotice), and failed \(urls.count - imported.count) font(s)"
                    } else {
                        fontsImportNotice = "Failed \(urls.count - imported.count) font(s)"
                    }
                }
                fontsCount = newCount
            }
            .padding()
            
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
            
            Divider()
            
            Spacer()
        }   //ScrollView
        .onAppear() {
            dismissAllCancellable?.cancel()
            dismissAllCancellable = modelData.dismissAllPublisher.sink { _ in
                fontsFolderPresenting = false
                fontsDetailPresenting = false
                optionsFormatPresenting = false
                optionsReaderEpubPresenting = false
                optionsReaderPdfPresenting = false
                optionsReaderCbzPresenting = false
                customDictViewerInfoPresenting = false
                customDictViewerTestPresenting = false
            }
            
            (customDictViewerEnabled, customDictViewerURLStored) = modelData.getCustomDictViewer()
            customDictViewerURL = customDictViewerURLStored?.absoluteString ?? ""
            customDictViewerURLMalformed = checkCustomDictViewerURL(value: customDictViewerURL)
        }
    }
    
    @ViewBuilder
    private func FontPreviewBuilder(fontId: String, fontInfo: FontInfo) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(fontId)
                Text(fontInfo.displayName ?? "")
                Text(fontInfo.localizedName ?? "")
                Text(fontInfo.fileURL?.lastPathComponent ?? "")
                Group {
                    Text("The quick brown fox jumps over the lazy dog and runs away.")
                    Divider()
                    
                    if fontInfo.languages.contains("en") {
                        Text("""
                            ABCDEFGHIJKLM
                            NOPQRSTUVWXYZ
                            abcdefghijklm
                            nopqrstuvwxyz
                            1234567890
                            """)
                        Divider()
                    }
                    if fontInfo.languages.contains("zh") {
                        Text(
                            """
                            汉体书写信息技术标准相容
                            档案下载使用界面简单
                            支援服务升级资讯专业制作
                            创意空间快速无线上网
                            ㈠㈡㈢㈣㈤㈥㈦㈧㈨㈩
                            AaBbCc ＡａＢｂＣｃ
                            """
                        )
                        Divider()
                    }
                    if fontInfo.languages.contains("ja") {
                        Text("""
                            あのイーハトーヴォの
                            すきとおった風、
                            夏でも底に冷たさをもつ青いそら、
                            うつくしい森で飾られたモリーオ市、
                            郊外のぎらぎらひかる草の波。
                            祇辻飴葛蛸鯖鰯噌庖箸
                            ABCDEFGHIJKLM
                            abcdefghijklm
                            1234567890
                            """)
                    }
                }.font(Font.custom(fontId, size: 25, relativeTo: .headline))
            }.padding()
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
    
    func removeFontRows(at offsets: IndexSet) {
        modelData.removeCustomFonts(at: offsets)
        modelData.reloadCustomFonts()
    }
}

struct ReaderOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderOptionsView().environmentObject(ModelData())
    }
}
