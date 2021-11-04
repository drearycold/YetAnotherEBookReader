//
//  VersionHistoryView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/1.
//

import SwiftUI

struct VersionHistoryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack{}.frame(height: 16)
                VStack(alignment: .leading, spacing: 4) {
                    header("Version 0.2.0")
                    textLine("Tighter Integration with Goodreads Sync Plugin's Custom Columns, and Will Record Current Reading Progress into Specified Column")
                    textLine("Recognize Custom Columns Used by Count Pages Plugin")
                    textLine("Ability to Navigate to BookInfo/Goodreads/Douban directly from RecentShelf's Book Context Menu")
                    textLine("Activity Logs Viewer to Help Troubleshooting Network Ralated Issues")
                    textLine("Reading Statistics and Position History Viewer to Track Your Time")
                    textLine("And Lots of UI Tweaks")
                }
                VStack(alignment: .leading, spacing: 4) {
                    header("Version 0.1.0")
                    textLine("Initial Release")
                    textLine("Supports Reading EPUB/PDF/CBZ")
                    textLine("Supports Interaction with calibre Context Server")
                }
            }
        }
        .frame(maxWidth: 500)
        .navigationTitle("Version History")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func header(_ header: String) -> some View {
        HStack(spacing: 4) {
            Text("★").hidden()
            Text(header).font(.title2).padding([.top, .bottom], 4)
        }
    }
    
    @ViewBuilder
    private func textLine(_ line: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("★")
            Text(line)
        }
    }
}

struct VersionHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        VersionHistoryView()
    }
}
