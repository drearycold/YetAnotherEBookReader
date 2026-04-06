//
//  YabrReaderNavigationView.swift
//  YetAnotherEBookReader
//
//  Created by Gemini CLI on 2024/03/26.
//

import SwiftUI
import ReadiumShared
import ReadiumNavigator

extension Array where Element == ReadiumShared.Link {
    var allHashesWithChildren: Set<Int> {
        var hashes = Set<Int>()
        for link in self {
            if !link.children.isEmpty {
                hashes.insert(link.hashValue)
                hashes.formUnion(link.children.allHashesWithChildren)
            }
        }
        return hashes
    }
}

struct YabrReaderNavigationView: View {
    @ObservedObject var viewModel: YabrReaderNavigationViewModel
    @State private var selectedTab = 0 // 0: Outline, 1: Bookmarks, 2: Highlights
    @State private var expandedHashes = Set<Int>()
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Tabs", selection: $selectedTab) {
                    Text("Outline").tag(0)
                    Text("Bookmarks").tag(1)
                    Text("Highlights").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                if selectedTab == 0 {
                    HStack {
                        Button("Expand All") {
                            withAnimation {
                                expandedHashes = viewModel.outline.allHashesWithChildren
                            }
                        }
                        Spacer()
                        Button("Collapse All") {
                            withAnimation {
                                expandedHashes.removeAll()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                List {
                    if selectedTab == 0 {
                        OutlineSection(links: viewModel.outline, expandedHashes: $expandedHashes, onNavigate: { link in
                            viewModel.onNavigateToLink?(link)
                        })
                    } else if selectedTab == 1 {
                        LocatorSection(locators: viewModel.bookmarks, title: "No Bookmarks") { locator in
                            viewModel.onNavigateToLocator?(locator)
                        }
                    } else {
                        LocatorSection(locators: viewModel.highlights, title: "No Highlights") { locator in
                            viewModel.onNavigateToLocator?(locator)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Navigation")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct OutlineSection: View {
    let links: [ReadiumShared.Link]
    @Binding var expandedHashes: Set<Int>
    let onNavigate: (ReadiumShared.Link) -> Void
    
    var body: some View {
        ForEach(links, id: \.hashValue) { link in
            OutlineRow(link: link, level: 0, expandedHashes: $expandedHashes, onNavigate: onNavigate)
        }
    }
}

struct OutlineRow: View {
    let link: ReadiumShared.Link
    let level: Int
    @Binding var expandedHashes: Set<Int>
    let onNavigate: (ReadiumShared.Link) -> Void
    
    var body: some View {
        let hasChildren = !link.children.isEmpty
        let isExpanded = expandedHashes.contains(link.hashValue)
        
        Group {
            HStack {
                Button(action: {
                    onNavigate(link)
                }) {
                    Text(link.title ?? "Untitled")
                        .padding(.leading, CGFloat(level * 20))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(BorderlessButtonStyle())
                
                if hasChildren {
                    Button(action: {
                        withAnimation {
                            if isExpanded {
                                expandedHashes.remove(link.hashValue)
                            } else {
                                expandedHashes.insert(link.hashValue)
                            }
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            
            if hasChildren && isExpanded {
                ForEach(link.children, id: \.hashValue) { child in
                    OutlineRow(link: child, level: level + 1, expandedHashes: $expandedHashes, onNavigate: onNavigate)
                }
            }
        }
    }
}

struct LocatorSection: View {
    let locators: [Locator]
    let title: String
    let onNavigate: (Locator) -> Void
    
    var body: some View {
        if locators.isEmpty {
            Text(title)
                .foregroundColor(.secondary)
        } else {
            ForEach(0..<locators.count, id: \.self) { index in
                let locator = locators[index]
                Button(action: {
                    onNavigate(locator)
                }) {
                    VStack(alignment: .leading) {
                        Text(locator.title ?? "Untitled")
                            .font(.headline)
                        if let text = locator.text.highlight {
                            Text(text)
                                .font(.subheadline)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}
