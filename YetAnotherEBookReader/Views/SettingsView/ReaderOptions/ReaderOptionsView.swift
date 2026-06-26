//
//  ReaderOptionsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/13.
//

import SwiftUI
import Combine

struct ReaderOptionsView: View {
    @StateObject private var viewModel: ReaderOptionsViewModel
    
    init(container: AppContainer? = nil, fontsManager: FontsManager? = nil) {
        let resolvedModel = container ?? AppContainer.shared ?? AppContainer()
        let resolvedFonts = fontsManager ?? resolvedModel.fontsManager
        self._viewModel = StateObject(wrappedValue: ReaderOptionsViewModel(container: resolvedModel, fontsManager: resolvedFonts))
    }

    var body: some View {
        List {
            Section(header: HStack {
                Text("Preferred Book Format")
                Spacer()
                Button(action:{
                    viewModel.optionsHelpFormat = true
                }) {
                    Image(systemName: "questionmark.circle")
                }
            }) {
                Picker("PreferredFormat", selection: viewModel.preferredFormatBinding) {
                    ForEach(Format.allCases.dropFirst(), id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .popover(isPresented: $viewModel.optionsHelpFormat) {
                    ReaderOptionsFormatHelpView()
                        .frame(maxWidth: 600, minHeight: 420)
                }
            }
            
            Section {
                VStack {
                    ForEach(Format.allCases.filter { (viewModel.container.sessionManager.formatReaderMap[$0]?.count ?? 0) > 0 }, id: \.self) { format in
                        HStack {
                            Text(format.rawValue)
                                .frame(minWidth: 64, alignment: .leading)
                                .padding([.leading], 8)
                            Picker("Prefered", selection: viewModel.preferredReaderBinding(for: format)) {
                                ForEach(viewModel.container.sessionManager.formatReaderMap[format]!, id: \.self) { reader in
                                    Text(reader.rawValue).tag(reader)
                                }
                            }.pickerStyle(SegmentedPickerStyle())
                        }
                    }
                }
                .popover(isPresented: $viewModel.optionsHelpReader) {
                    ReaderOptionsHelpView()
                }
            } header: {
                HStack {
                    Text("Prefered Reader")
                    Spacer()
                    Button(action: {
                        viewModel.optionsHelpReader = true
                    }) {
                        Image(systemName: "questionmark.circle")
                    }
                    
                }
            }

            Section(header: HStack {
                Text("Custom Fonts for \(ReaderType.YabrEPUB.rawValue)")
                Spacer()
                Button(action:{
                    viewModel.optionsHelpFont = true
                }) {
                    Image(systemName: "questionmark.circle")
                }
            }, footer: HStack {
                Text(viewModel.fontsImportNotice).font(.caption)
            }) {
                HStack {
                    Text("Loaded")
                    Text("\(viewModel.fontsManager.userFontInfos.count)")
                    Text("font(s)")
                    Spacer()
                    
                    Button(action:{
                        viewModel.startViewDetails()
                    }) {
                        Text("View")
                    }
                    .disabled(viewModel.fontsManager.userFontInfos.isEmpty)
                    .buttonStyle(.borderless)
                    .sheet(isPresented: $viewModel.fontsDetailPresenting, onDismiss: {
                        viewModel.handleDetailsDismiss()
                    }) {
                        NavigationView {
                            List {
                                ForEach(
                                    viewModel.fontsManager.userFontInfos.sorted {
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
                                }.onDelete(perform: viewModel.removeFontRows)
                            }.navigationTitle("Favorite Fonts")
                        }
                    }
                }
                .popover(isPresented: $viewModel.optionsHelpFont, attachmentAnchor: .point(.bottom), content: {
                    ReaderOptionsFontHelpView()
                        .frame(maxWidth: 600, minHeight: 240)
                })
                
                Button(action:{
                    viewModel.startImport()
                }) {
                    Text("Import Fonts")
                }
                .sheet(isPresented: $viewModel.fontsFolderPresenting, onDismiss: {
                    viewModel.fontsFolderPresenting = false
                }) {
                    FontImportPicker(fontURLs: $viewModel.fontsFolderPicked)
                }
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
}

struct ReaderOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        let container = AppContainer()
        NavigationView {
            ReaderOptionsView(container: container, fontsManager: container.fontsManager)
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}
