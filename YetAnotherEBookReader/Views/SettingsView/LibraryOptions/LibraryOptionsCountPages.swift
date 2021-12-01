//
//  LibraryOptionsCountPages.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/4.
//

import SwiftUI

struct LibraryOptionsCountPages: View {
    let library: CalibreLibrary
    let configuration: CalibreDSReaderHelperConfiguration

    @Binding var countPages: CalibreLibraryCountPages
    @State private var countPagesDefault: CalibreLibraryCountPages = .init()
    @State private var countPagesState = CalibreLibraryCountPages()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Count Pages Columns")
                .font(.title3)

            Toggle("Override Server Settings", isOn: $countPagesState._isOverride)
            
            Group {
                Toggle("Enabled", isOn: $countPagesState._isEnabled)
                
                VStack(spacing: 4) {
                    columnPickerRowView(
                        label: "Page Count",
                        selection: $countPagesState.pageCountCN,
                        source: library.customColumnInfoNumberKeys)
                    columnPickerRowView(
                        label: "Word Count",
                        selection: $countPagesState.wordCountCN,
                        source: library.customColumnInfoNumberKeys)
                    columnPickerRowView(
                        label: "Flesch Reading Ease",
                        selection: $countPagesState.fleschReadingEaseCN,
                        source: library.customColumnInfoNumberKeys)
                    columnPickerRowView(
                        label: "Flesch-Kincaid Grade",
                        selection: $countPagesState.fleschKincaidGradeCN,
                        source: library.customColumnInfoNumberKeys)
                    columnPickerRowView(
                        label: "Gunning Fog Index",
                        selection: $countPagesState.gunningFogIndexCN,
                        source: library.customColumnInfoNumberKeys)
                    
                }.padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                .disabled(!countPagesState.isEnabled())
            }.disabled(!countPagesState.isOverride())
        }   //ends VStack
        .onAppear {
            countPagesDefault = .init(libraryId: library.id, configuration: configuration)
            if countPages.isOverride() {
                countPagesState._isOverride = true
            } else {
                countPagesState = countPagesDefault
            }
        }
        .onChange(of: countPagesState._isOverride) { [countPagesState] newValue in
            if newValue && countPagesState.isOverride() {
                //let onDisappear handle changing
            } else if newValue {   //changing to override, replace show user settings stored in countPages
                countPages._isOverride = true
                self.countPagesState = countPages
            } else if countPagesState.isOverride() {     //changing to default, replace countPagesState with countPagesDefault
                self.countPages = countPagesState
                self.countPages._isOverride = false
                self.countPagesState = countPagesDefault
            }
        }
        .onDisappear {
            if countPagesState.isOverride() {
                countPages = countPagesState
            }
        }
    }
    
    
    @ViewBuilder
    private func columnPickerRowView(label: String, selection: Binding<String>, source: [CalibreCustomColumnInfo]) -> some View {
        HStack {
            Text(label)
            Spacer()
            Picker(source.first { "#" + $0.label == selection.wrappedValue }?.name ?? "not set",
                selection: selection) {
                ForEach(source.reduce(
                    into: [("not set", "#")]) {
                    $0.append(($1.name, "#" + $1.label))
                }, id: \.1) {    //(name, label), prepend label with "#"
                    Text("\($0) (\($1))").tag($1)
                }
            }.pickerStyle(MenuPickerStyle()).frame(minWidth: 150, alignment: .leading)
        }
    }
}

struct LibraryOptionsCountPages_Previews: PreviewProvider {
    @State static private var library = CalibreLibrary(server: CalibreServer(name: "", baseUrl: "", publicUrl: "", username: "", password: ""), key: "Default", name: "Default")

    @State static private var countPages = CalibreLibraryCountPages()
    static private var configuration = CalibreDSReaderHelperConfiguration()

    static var previews: some View {
        LibraryOptionsCountPages(library: library, configuration: configuration, countPages: $countPages)
    }
}
