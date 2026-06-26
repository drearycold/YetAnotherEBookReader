//
//  SectionShelfViewModel.swift
//  YetAnotherEBookReader
//
//  Created by opencode on 2026-06-18.
//

import Foundation
import Combine
import ShelfView
import UIKit

@MainActor @available(macCatalyst 14.0, *)
final class SectionShelfViewModel: ObservableObject {
    private let modelData: ModelData
    private var cancellables = Set<AnyCancellable>()
    
    @Published var shelfSections = [ShelfModelSection]()
    @Published var pickedLibraries = Set<String>()
    @Published var menuElements = [UIMenuElement]()
    
    init(modelData: ModelData) {
        self.modelData = modelData
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        modelData.discoverShelfModelSubject
            .collect(.byTime(RunLoop.main, .seconds(1)))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shelfModelsArray in
                guard let self = self, let shelfModels = shelfModelsArray.last else { return }
                self.updateShelfModels(shelfModels)
            }
            .store(in: &cancellables)
    }
    
    func refreshShelf() {
        modelData.shelfDataModel.refresh()
    }
    
    func downloadSelectedBooks(bookIds: Set<String>) {
        bookIds.forEach { bookId in
            guard let book = modelData.getBook(for: bookId),
                  let format = modelData.getPreferredFormat(for: book)
            else { return }
            modelData.addToShelf(book: book, formats: [format])
        }
    }
    
    private func updateShelfModels(_ shelfModels: [ShelfModelSection]) {
        let librarySet = Set<CalibreLibrary>(shelfModels.compactMap { shelfModel -> CalibreLibrary? in
            guard let libraryId = ModelData.parseShelfSectionId(sectionId: shelfModel.sectionId) else { return nil }
            return modelData.calibreLibraries[libraryId]
        })
        
        let topMenuElements = [
            UIAction(title: "    Reset") { [weak self] _ in
                self?.pickedLibraries.removeAll(keepingCapacity: true)
                self?.modelData.discoverShelfModelSubject.send(self?.modelData.bookModelSection ?? [])
            }
        ] + librarySet.sorted(by: { $0.name < $1.name })
        .map { library -> UIAction in
            let isPicked = pickedLibraries.contains(library.id)
            return UIAction(title: (isPicked ? " ✓ " : "    ") + library.name + " on " + library.server.name) { [weak self] _ in
                self?.pickedLibraries.formSymmetricDifference([library.id])
                self?.modelData.discoverShelfModelSubject.send(self?.modelData.bookModelSection ?? [])
            }
        }
        
        menuElements = topMenuElements
        
        pickedLibraries.formIntersection(
            shelfModels.compactMap { ModelData.parseShelfSectionId(sectionId: $0.sectionId) }
        )
        
        shelfSections = shelfModels.filter {
            guard let libraryId = ModelData.parseShelfSectionId(sectionId: $0.sectionId) else { return false }
            return pickedLibraries.isEmpty || pickedLibraries.contains(libraryId)
        }
    }
}
