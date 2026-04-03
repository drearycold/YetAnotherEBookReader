//
//  YabrReadiumPDFViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/9/27.
//

import Foundation
import UIKit
import ReadiumNavigator
import ReadiumShared

import ReadiumAdapterGCDWebServer

final class YabrReadiumPDFViewController: YabrReadiumReaderViewController, PDFNavigatorDelegate {
    
    init(publication: Publication, initialLocation: Locator?, environment: YabrReadiumEnvironment) {
        let navigator: PDFNavigatorViewController
        do {
            navigator = try PDFNavigatorViewController(publication: publication, initialLocation: initialLocation, httpServer: environment.httpServer)
        } catch {
            fatalError("Failed to initialize PDFNavigatorViewController: \(error)")
        }
        
        super.init(navigator: navigator, publication: publication, initialLocation: initialLocation, environment: environment)
        
        navigator.delegate = self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        super.navigator(navigator, locationDidChange: locator)
        
        Task { [weak self] in
            guard let self = self else { return }
            var updatedReadingPosition = (Double(), Double(), [String: Any](), "")
            
            updatedReadingPosition.2["pageNumber"] = locator.locations.position
            let positionsResult = await self.publication.positionsByReadingOrder()
            updatedReadingPosition.2["maxPage"] = (try? positionsResult.get())?.first?.count ?? 1

            updatedReadingPosition.2["pageOffsetX"] = 0
            
            updatedReadingPosition.0 = locator.locations.progression ?? 0.0
            updatedReadingPosition.1 = locator.locations.totalProgression ?? 0.0
            
            let tocResult = await self.publication.tableOfContents()
            let tableOfContents = (try? tocResult.get()) ?? []
            
            if let title = locator.title {
                updatedReadingPosition.3 = title
            } else if let fragment = locator.locations.fragments.first,
                      let tocLink = tableOfContents.firstDeep(withFRAGMENT: fragment),
                      let tocTitle = tocLink.title {
                updatedReadingPosition.3 = tocTitle
            } else if let fragment = locator.locations.fragments.first,
                      let locPageNumberValue = fragment.split(separator: "=").last,
                      let locPageNumber = Int(locPageNumberValue),
                        let tocLink = tableOfContents.filter( { link in
                            guard let tocFragmentIndex = link.href.firstIndex(of: "#"),
                                  let tocFragment = link.href[tocFragmentIndex..<link.href.endIndex] as Substring?,
                                  let pageNumberValue = tocFragment.split(separator: "=").last,
                                  let pageNumber = Int(pageNumberValue),
                                  pageNumber <= locPageNumber
                            else { return false }
                            
                            return true
                        }).last,
                      let tocTitle = tocLink.title {
                updatedReadingPosition.3 = tocTitle
            } else {
                updatedReadingPosition.3 = "Unknown Title"
            }
            
            DispatchQueue.main.async {
                self.readiumMetaSource?.yabrReadiumReadPosition(self, update: updatedReadingPosition)
            }
        }
    }
}

fileprivate extension Array where Element == Link {
    func firstDeep(withFRAGMENT fragment: String) -> Link? {
        return first {
            URL(string: $0.href)?.fragment == fragment || $0.children.firstDeep(withFRAGMENT: fragment) != nil
        }
    }
}
