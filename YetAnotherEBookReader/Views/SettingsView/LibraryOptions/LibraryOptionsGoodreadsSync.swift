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
    
    @State private var goodreadsSyncDefault: CalibreLibraryGoodreadsSync = .init()
    @State private var goodreadsSyncState = CalibreLibraryGoodreadsSync()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Goodreads Sync Columns")
                .font(.title3)

            Toggle("Override Server Settings", isOn: $goodreadsSyncState._isOverride)
            Group {
                Toggle("Enabled", isOn: $goodreadsSyncState._isEnabled)
                
                VStack(spacing: 4) {
                    columnPickerRowView(
                        label: "Tags",
                        selection: $goodreadsSyncState.tagsColumnName,
                        source: library.customColumnInfoMultiTextKeys)
                    columnPickerRowView(
                        label: "Rating",
                        selection: $goodreadsSyncState.ratingColumnName,
                        source: library.customColumnInfoRatingKeys)
                    columnPickerRowView(
                        label: "Date read",
                        selection: $goodreadsSyncState.dateReadColumnName,
                        source: library.customColumnInfoDateKeys)
                    columnPickerRowView(
                        label: "Review text",
                        selection: $goodreadsSyncState.reviewColumnName,
                        source: library.customColumnInfoTextKeys)
                    columnPickerRowView(
                        label: "Reading progress",
                        selection: $goodreadsSyncState.readingProgressColumnName,
                        source: library.customColumnInfoNumberKeys)
                    
                }.padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                .disabled(!goodreadsSyncState.isEnabled())
            }.disabled(!goodreadsSyncState.isOverride())
        }   //ends VStack
        .onAppear {
            goodreadsSyncDefault = .init(libraryId: library.id, configuration: configuration)
            if goodreadsSync.isOverride() {
                goodreadsSyncState._isOverride = true
            } else {
                goodreadsSyncState = goodreadsSyncDefault
            }
        }
        .onChange(of: goodreadsSyncState._isOverride) { [goodreadsSyncState] newValue in
            if newValue && goodreadsSyncState.isOverride() {
                //let onDisappear handle changing
            } else if newValue {   //changing to override, replace show user settings stored in goodreadsSync
                goodreadsSync._isOverride = true
                self.goodreadsSyncState = goodreadsSync
            } else if goodreadsSyncState.isOverride() {     //changing to default, replace goodreadsSyncState with goodreadsSyncDefault
                self.goodreadsSync = goodreadsSyncState
                self.goodreadsSync._isOverride = false
                self.goodreadsSyncState = goodreadsSyncDefault
            }
        }
        .onDisappear {
            if goodreadsSyncState.isOverride() {
                goodreadsSync = goodreadsSyncState
            }
        }
    }   //ends body
    
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

struct LibraryOptionsGoodreadsSYnc_Previews: PreviewProvider {
    @State static private var library = CalibreLibrary(server: CalibreServer(name: "", baseUrl: "", publicUrl: "", username: "", password: ""), key: "Default", name: "Default")

    @State static private var goodreadsSync = CalibreLibraryGoodreadsSync()
    static private var configuration = CalibreDSReaderHelperConfiguration()
    
    static var previews: some View {
        LibraryOptionsGoodreadsSync(library: library, configuration: configuration, goodreadsSync: $goodreadsSync)
    }
}
