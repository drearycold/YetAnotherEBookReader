import SwiftUI

@MainActor
final class ReadingPositionDetailViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let position: BookDeviceReadingPosition
    let selectedFormat: Format
    let availableReaders: [ReaderType]

    @Published var selectedFormatReader: ReaderType
    @Published var alertItem: AlertItem?

    private let listModel: ReadingPositionListViewModel
    let percentFormatter = NumberFormatter()
    let dateFormatter = DateFormatter()
    private var bookObserver: Task<Void, Never>?

    init(listModel: ReadingPositionListViewModel, position: BookDeviceReadingPosition) {
        self.listModel = listModel
        self.position = position
        let reader = ReaderType(rawValue: position.readerName) ?? .UNSUPPORTED
        selectedFormatReader = reader
        selectedFormat = listModel.format(for: reader)
        availableReaders = listModel.readers(for: selectedFormat)

        percentFormatter.numberStyle = .percent
        percentFormatter.minimumFractionDigits = 1
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        dateFormatter.timeZone = .current
    }

    deinit { bookObserver?.cancel() }

    func start() {
        guard bookObserver == nil else { return }
        let identity = listModel.book.inShelfId
        let books = listModel.bookRepository.observeBook(id: identity)
        bookObserver = Task { [weak self] in
            for await book in books {
                guard !Task.isCancelled, let self else { return }
                if let book, book.inShelfId == identity {
                    self.objectWillChange.send()
                    self.listModel.book = book
                }
            }
        }
    }

    func stop() {
        bookObserver?.cancel()
        bookObserver = nil
    }

    var isSelectedFormatCached: Bool {
        listModel.canContinueReading(at: position, format: selectedFormat, readerType: selectedFormatReader)
    }

    func readSelectedFormat(targetWorkspaceID: UUID?) {
        alertItem = listModel.continueReading(
            at: position,
            format: selectedFormat,
            readerType: selectedFormatReader,
            targetWorkspaceID: targetWorkspaceID
        )
    }
}

