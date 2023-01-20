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

    @State private var optionsHelpFormat = false
    @State private var optionsHelpReader = false
    @State private var optionsHelpFont = false
    
    @State private var fontsFolderPresenting = false
    @State private var fontsFolderPicked = [URL]()
    @State private var fontsDetailPresenting = false
    @State private var fontsCount = 0
    @State private var fontsImportNotice = ""
    
    @State private var dismissAllCancellable: AnyCancellable?
    
    var body: some View {
        List {
            Section(header: HStack {
                Text("Preferred Book Format")
                Spacer()
                Button(action:{
                    optionsHelpFormat = true
                }) {
                    Image(systemName: "questionmark.circle")
                }
            }) {
                Picker("PreferredFormat", selection: preferredReaderTypeBinding()) {
                    ForEach(Format.allCases.dropFirst(), id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .popover(isPresented: $optionsHelpFormat) {
                    ReaderOptionsFormatHelpView()
                        .frame(maxWidth: 600, minHeight: 420)
                }
            }
            
            Section {
                VStack {
                    ForEach(Format.allCases.filter { (modelData.formatReaderMap[$0]?.count ?? 0) > 0 }, id: \.self) { format in
                        HStack {
                            Text(format.rawValue)
                                .frame(minWidth: 64, alignment: .leading)
                                .padding([.leading], 8)
                            Picker("Prefered", selection: preferredReaderTypeBinding(for: format)) {
                                ForEach(modelData.formatReaderMap[format]!, id: \.self) { reader in
                                    Text(reader.rawValue).tag(reader)
                                }
                            }.pickerStyle(SegmentedPickerStyle())
                        }
                    }
                }
                .popover(isPresented: $optionsHelpReader) {
                    ReaderOptionsHelpView()
                }
            } header: {
                HStack {
                    Text("Prefered Reader")
                    Spacer()
                    Button(action: {
                        optionsHelpReader = true
                    }) {
                        Image(systemName: "questionmark.circle")
                    }
                    
                }
            }

            Section(header: HStack {
                Text("Custom Fonts for \(ReaderType.YabrEPUB.rawValue)")
                Spacer()
                Button(action:{
                    optionsHelpFont = true
                }) {
                    Image(systemName: "questionmark.circle")
                }
            }, footer: HStack {
                Text(fontsImportNotice).font(.caption)
            }) {
                HStack {
                    Text("Loaded")
                    Text("\(modelData.userFontInfos.count)")
                    Text("font(s)")
                    Spacer()
                    
                    Button(action:{
                        fontsCount = modelData.userFontInfos.count
                        fontsDetailPresenting = true
                    }) {
                        Text("View")
                    }
                    .disabled(modelData.userFontInfos.isEmpty)
                    .buttonStyle(.borderless)
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
                }
                .popover(isPresented: $optionsHelpFont, attachmentAnchor: .point(.bottom), content: {
                    ReaderOptionsFontHelpView()
                        .frame(maxWidth: 600, minHeight: 240)
                })
                
                Button(action:{
                    fontsCount = modelData.userFontInfos.count
                    fontsFolderPresenting = true
                }) {
                    Text("Import Fonts")
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
            }
            
        }
        .onAppear() {
            dismissAllCancellable?.cancel()
            dismissAllCancellable = modelData.dismissAllSubject.sink { _ in
                fontsFolderPresenting = false
                fontsDetailPresenting = false
                optionsHelpFormat = false
                optionsHelpReader = false
                optionsHelpFont = false
            }
        }
        .navigationTitle("Reader Options")
        .navigationBarTitleDisplayMode(.inline)
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
    
    
    func removeFontRows(at offsets: IndexSet) {
        modelData.removeCustomFonts(at: offsets)
        modelData.reloadCustomFonts()
    }
}

struct ReaderOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ReaderOptionsView().environmentObject(ModelData())
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
