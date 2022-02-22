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
//    @State private var countPagesDefault: CalibreLibraryCountPages = .init()
//    @State private var countPagesState = CalibreLibraryCountPages()
    
    private let columnNotSetEntry = CalibreCustomColumnInfo(label: "", name: "not set", datatype: "", editable: false, display: CalibreCustomColumnDisplayInfo(description: "", isNames: nil, compositeTemplate: nil, compositeSort: nil, useDecorations: nil, makeCategory: nil, containsHtml: nil, numberFormat: nil, headingPosition: nil, interpretAs: nil, allowHalfStars: nil), normalized: false, num: 0, isMultiple: false, multipleSeps: [:])
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Count Pages Columns")
                .font(.title3)

//            Toggle("Override Server Settings", isOn: $countPages._isOverride)
            
            Group {
                Toggle("Enabled", isOn: $countPages._isEnabled)
                
                VStack(spacing: 4) {
                    columnPickerRowView(
                        label: "Page Count",
                        selection: $countPages.pageCountCN,
                        unmatched: library.customColumnInfoNumberKeys
                    )
                    columnPickerRowView(
                        label: "Word Count",
                        selection: $countPages.wordCountCN,
                        unmatched: library.customColumnInfoNumberKeys)
                    columnPickerRowView(
                        label: "Flesch Reading Ease",
                        selection: $countPages.fleschReadingEaseCN,
                        unmatched: library.customColumnInfoNumberKeys)
                    columnPickerRowView(
                        label: "Flesch-Kincaid Grade",
                        selection: $countPages.fleschKincaidGradeCN,
                        unmatched: library.customColumnInfoNumberKeys)
                    columnPickerRowView(
                        label: "Gunning Fog Index",
                        selection: $countPages.gunningFogIndexCN,
                        unmatched: library.customColumnInfoNumberKeys)
                    
                }
                .padding([.leading, .trailing], 8)
                .disabled(!countPages.isEnabled())
            }
//            .disabled(!countPagesState.isOverride())
        }   //ends VStack
//        .onAppear {
//            countPagesDefault = .init(libraryId: library.id, configuration: configuration)
//            if countPages.isOverride() {
//                countPagesState._isOverride = true
//            } else {
//                countPagesState = countPagesDefault
//            }
//        }
//        .onChange(of: countPagesState._isOverride) { [countPagesState] newValue in
//            if newValue && countPagesState.isOverride() {
//                //let onDisappear handle changing
//            } else if newValue {   //changing to override, replace show user settings stored in countPages
//                countPages._isOverride = true
//                self.countPagesState = countPages
//            } else if countPagesState.isOverride() {     //changing to default, replace countPagesState with countPagesDefault
//                self.countPages = countPagesState
//                self.countPages._isOverride = false
//                self.countPagesState = countPagesDefault
//            }
//        }
//        .onDisappear {
//            if countPagesState.isOverride() {
//                countPages = countPagesState
//            }
//        }
    }
    
    @ViewBuilder
    private func columnPickerRowView(label: String, selection: Binding<String>, unmatched: [CalibreCustomColumnInfo]) -> some View {
        HStack {
            Text(label)
            Spacer()
            Picker(customColumnInfos(unmatched: unmatched, setting: selection.wrappedValue).first { "#" + $0.label == selection.wrappedValue }?.name ?? "not set",
                selection: selection) {
                ForEach(
                    customColumnInfos(unmatched: unmatched, setting: selection.wrappedValue).map {
                        ($0.name, "#" + $0.label)
                    }, id: \.1) {    //(name, label), prepend label with "#"
                    Text("\($0) (\($1))").tag($1)
                }
            }.pickerStyle(MenuPickerStyle()).frame(minWidth: 150, alignment: .leading)
        }
    }
    
    private func customColumnInfos(unmatched: [CalibreCustomColumnInfo], setting: String) -> [CalibreCustomColumnInfo] {
        var result = unmatched
        result.append(columnNotSetEntry)
        if let set = library.customColumnInfos[setting.removingPrefix("#")] {
            result.append(set)
        }
        return result.sorted{ $0.name < $1.name }
    }
    
}

struct LibraryOptionsCountPages_Previews: PreviewProvider {
    @State static private var library = CalibreLibrary(server: CalibreServer(name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "Default", name: "Default")

    @State static private var countPages = CalibreLibraryCountPages()
    static private var configuration = CalibreDSReaderHelperConfiguration()

    static var previews: some View {
        LibraryOptionsCountPages(library: library, configuration: configuration, countPages: $countPages)
    }
}
