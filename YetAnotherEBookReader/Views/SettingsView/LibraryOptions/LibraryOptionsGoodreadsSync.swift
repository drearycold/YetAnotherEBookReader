//
//  LibraryOptionsGoodreadsSYnc.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/29.
//

import SwiftUI

struct LibraryOptionsGoodreadsSync: View {
    let library: CalibreLibrary
    let configuration: CalibreDSReaderHelperConfiguration
    
    @Binding var goodreadsSync: CalibreLibraryGoodreadsSync
    
    private let columnNotSetEntry = CalibreCustomColumnInfo(label: "", name: "not set", datatype: "", editable: false, display: CalibreCustomColumnDisplayInfo(description: "", isNames: nil, compositeTemplate: nil, compositeSort: nil, useDecorations: nil, makeCategory: nil, containsHtml: nil, numberFormat: nil, headingPosition: nil, interpretAs: nil, allowHalfStars: nil), normalized: false, num: 0, isMultiple: false, multipleSeps: [:])

    var body: some View {
        Section(header: Text("Goodreads Sync Columns")) {
            Toggle("Enabled", isOn: $goodreadsSync._isEnabled)
            
            Group {
                columnPickerRowView(
                    label: "Tags",
                    selection: $goodreadsSync.tagsColumnName,
                    unmatched: library.customColumnInfoMultiTextKeys)
                columnPickerRowView(
                    label: "Rating",
                    selection: $goodreadsSync.ratingColumnName,
                    unmatched: library.customColumnInfoRatingKeys)
                columnPickerRowView(
                    label: "Date read",
                    selection: $goodreadsSync.dateReadColumnName,
                    unmatched: library.customColumnInfoDateKeys)
                columnPickerRowView(
                    label: "Review text",
                    selection: $goodreadsSync.reviewColumnName,
                    unmatched: library.customColumnInfoTextKeys)
                columnPickerRowView(
                    label: "Reading progress",
                    selection: $goodreadsSync.readingProgressColumnName,
                    unmatched: library.customColumnInfoNumberKeys)
                
            }
            .disabled(!goodreadsSync.isEnabled())
        }   //ends VStack
        
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
            }.pickerStyle(MenuPickerStyle()).frame(minWidth: 150, alignment: .trailing)
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

struct LibraryOptionsGoodreadsSYnc_Previews: PreviewProvider {
    @State static private var library = CalibreLibrary(server: CalibreServer(uuid: .init(), name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "Default", name: "Default")

    @State static private var goodreadsSync = CalibreLibraryGoodreadsSync()
    static private var configuration = CalibreDSReaderHelperConfiguration()
    
    static var previews: some View {
        NavigationView {
            Form {
                LibraryOptionsGoodreadsSync(library: library, configuration: configuration, goodreadsSync: $goodreadsSync)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
