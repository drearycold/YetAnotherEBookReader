//
//  LibraryOptionsGoodreadsSYnc.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/29.
//

import SwiftUI

struct LibraryOptionsGoodreadsSync: View {
    let library: CalibreLibrary

    @Binding var goodreadsSync: CalibreLibraryGoodreadsSync
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable", isOn: $goodreadsSync._isEnabled)
                .font(.title2)
            
            Group {
                Text("Synchronisable Custom Columns")
                    .font(.title2)
                    .padding(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                VStack(spacing: 8) {

                    columnPickerRowView(
                        label: "Tags",
                        selection: $goodreadsSync.tagsColumnName,
                        source: library.customColumnInfoMultiTextKeys)
                    columnPickerRowView(
                        label: "Rating",
                        selection: $goodreadsSync.ratingColumnName,
                        source: library.customColumnInfoRatingKeys)
                    columnPickerRowView(
                        label: "Date read",
                        selection: $goodreadsSync.dateReadColumnName,
                        source: library.customColumnInfoDateKeys)
                    columnPickerRowView(
                        label: "Review text",
                        selection: $goodreadsSync.reviewColumnName,
                        source: library.customColumnInfoTextKeys)
                    columnPickerRowView(
                        label: "Reading progress",
                        selection: $goodreadsSync.readingProgressColumnName,
                        source: library.customColumnInfoNumberKeys)
                    
                }.padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto Syncing with Goodreads Account")
                        .font(.title2)

                    HStack {
                        Text("Profile:").padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0))
                        TextField("Name", text: $goodreadsSync.profileName)
                            .keyboardType(.alphabet)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .border(Color(UIColor.separator))
                    }
                    Text("We are working on the ability to update reading progress and shelf status to goodreads.com automatically. Please stay tuned.")
                        .font(.caption)
                        .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }   //ends profile
                
                Divider()
                
                Toggle("Set as Server-wide Default", isOn: $goodreadsSync._isDefault)
                
            }   //ends Group
            .disabled(!goodreadsSync.isEnabled())
        }   //ends VStack
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
    
    static var previews: some View {
        LibraryOptionsGoodreadsSync(library: library, goodreadsSync: $goodreadsSync)
    }
}
