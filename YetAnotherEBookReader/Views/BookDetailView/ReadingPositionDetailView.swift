//
//  ReadingPositionDetailView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/25.
//

import SwiftUI

struct ReadingPositionDetailView: View {
    @Environment(\.readerWorkspaceID) var readerWorkspaceID
    @Environment(\.dynamicTypeSize) private var textSize
    @StateObject private var viewModel: ReadingPositionDetailViewModel

    init(viewModel: @autoclosure @escaping () -> ReadingPositionDetailViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        List {
            Section {
                Button(action: {
                    viewModel.readSelectedFormat(targetWorkspaceID: readerWorkspaceID)
                }) {
                    Group {
                        if textSize.isAccessibilitySize {
                            VStack(spacing: 8) {
                                Image(systemName: "play.fill").accessibilityHidden(true)
                                Text("Continue Reading")
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Label("Continue Reading", systemImage: "play.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.isSelectedFormatCached)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("reading-position.continue")
            } footer: {
                if !viewModel.isSelectedFormatCached {
                    if viewModel.selectedFormatReader == .UNSUPPORTED {
                        Text("No reader can open this saved position.")
                    } else {
                        Text("Download \(viewModel.selectedFormat.rawValue) first to continue from here.")
                    }
                }
            }

            Section(header: Text("Reader")) {
                if viewModel.availableReaders.count > 1 {
                    if textSize.isAccessibilitySize {
                        readerPicker.pickerStyle(.inline).labelsHidden()
                    } else {
                        readerPicker.pickerStyle(.segmented)
                    }
                } else {
                    row("Reader", viewModel.selectedFormatReader.rawValue)
                }
            }

            Section(header: Text("Last Position")) {
                if viewModel.position.structuralStyle == 1, viewModel.position.lastReadBook.isEmpty == false {
                    row("Book", viewModel.position.lastReadBook)
                }
                let chapter = viewModel.position.lastReadChapter.trimmingCharacters(in: .whitespacesAndNewlines)
                if chapter.isEmpty {
                    row("Page", viewModel.position.lastReadPage.description)
                } else {
                    row("Section", chapter)
                }
                HStack {
                    Text("Progress")
                    Spacer()
                    Text(viewModel.percentFormatter.string(from: NSNumber(value: viewModel.position.lastChapterProgress / 100)) ?? "")
                    Text("/")
                    Text(viewModel.percentFormatter.string(from: NSNumber(value: viewModel.position.lastProgress / 100)) ?? "")
                }
                row("Time", viewModel.dateFormatter.string(from: Date(timeIntervalSince1970: viewModel.position.epoch)))
                row("Device", viewModel.position.id)
            }

#if DEBUG
            Section {
                DisclosureGroup("Debug") {
                    row("Entry", "\(viewModel.position.lastReadPage) / \(viewModel.position.maxPage)")
                    row("Position", "(\(viewModel.position.lastPosition.map(String.init).joined(separator: ":")))")
                    HStack {
                        Text("CFI")
                        Spacer()
                        Text(viewModel.position.cfi.replacingOccurrences(of: ";", with: ";\n")).lineLimit(10)
                    }
                    row("Epoch", viewModel.position.epoch.description)
                    if viewModel.position.structuralStyle == 1, viewModel.position.lastReadBook.isEmpty == false {
                        row("Bundle Progress", viewModel.percentFormatter.string(from: NSNumber(value: viewModel.position.lastBundleProgress / 100)) ?? "")
                    }
                }
            }
#endif
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Reading Position")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $viewModel.alertItem) { item in
            Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
        }
        .accessibilityIdentifier("screen.reading-position")
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private var readerPicker: some View {
        Picker("Reader", selection: $viewModel.selectedFormatReader) {
            ForEach(ReaderType.allCases) { type in
                if viewModel.availableReaders.contains(type) {
                    Text(type.rawValue).tag(type)
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ReadingPositionDetailView_Previews: PreviewProvider {
    static let container = AppContainer(mock: true)

    static var previews: some View {
        if let book = container.bookManager.booksInShelf.values.first,
           let position = container.readingPositionRepository.getPositions(for: book).first {
            let listModel = ReadingPositionListViewModel(
                container: container,
                book: book,
                positions: container.readingPositionRepository.getPositions(for: book)
            )
            NavigationView {
                ReadingPositionDetailView(
                    viewModel: ReadingPositionDetailViewModel(
                        listModel: listModel,
                        position: position
                    )
                )
            }
        }
    }
}
