//
//  EpubReadiumReaderContainer.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/5/29.
//

import Foundation
import R2Shared
import R2Navigator

class EpubReadiumReaderContainer: EPUBViewController {
    var modelData: ModelData?
    var updatedReadingPosition = (Double(), Double(), [String: Any](), "")

    let delegate = EpubReadiumReaderContainerNavigatorDelegate()

    func open() {
        let closeItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction(handler: { [self] _ in
            dismiss(animated: true, completion: nil)
            
            modelData?.updatedReadingPosition.lastChapterProgress = updatedReadingPosition.0 * 100
            modelData?.updatedReadingPosition.lastProgress = updatedReadingPosition.1 * 100
            
            modelData?.updatedReadingPosition.lastReadPage = updatedReadingPosition.2["pageNumber"] as? Int ?? 1
            modelData?.updatedReadingPosition.lastPosition[0] = updatedReadingPosition.2["pageNumber"] as? Int ?? 1
            modelData?.updatedReadingPosition.lastPosition[1] = updatedReadingPosition.2["pageOffsetX"] as? Int ?? 0
            modelData?.updatedReadingPosition.lastPosition[2] = updatedReadingPosition.2["pageOffsetY"] as? Int ?? 0
            
            
            modelData?.updatedReadingPosition.lastReadChapter = updatedReadingPosition.3
            
            modelData?.updatedReadingPosition.readerName = "ReadiumReader"
        }))
        
        navigationItem.leftBarButtonItem = closeItem
        
        moduleDelegate = self
        if let navigator = navigator as? EPUBNavigatorViewController {
            delegate.container = self
            navigator.delegate = delegate
            
            
        }
    }
}

extension EpubReadiumReaderContainer: ReaderModuleDelegate {
    func presentAlert(_ title: String, message: String, from viewController: UIViewController) {
        print("ReaderModuleDelegateImpl alert \(title) \(message)")
    }
    
    func presentError(_ error: Error?, from viewController: UIViewController) {
        print("ReaderModuleDelegateImpl error \(error)")
    }
}

extension EpubReadiumReaderContainer: ReaderFormatModuleDelegate {
    func presentOutline(of publication: Publication, delegate: OutlineTableViewControllerDelegate?, from viewController: UIViewController) {
        
    }
    
    func presentDRM(for publication: Publication, from viewController: UIViewController) {
        
    }
}

class EpubReadiumReaderContainerNavigatorDelegate: EPUBNavigatorDelegate {
    var container: EpubReadiumReaderContainer?
    
    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        print("EpubReadiumReaderContainerNavigatorDelegate \(error)")
    }
    
    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        print("EpubReadiumReaderContainerNavigatorDelegate \(locator)")
        if let index = container?.publication.readingOrder.firstIndex(withHREF: locator.href) {
            container?.updatedReadingPosition.2["pageNumber"] = index + 1
        } else {
            container?.updatedReadingPosition.2["pageNumber"] = 1
        }
        
        container?.updatedReadingPosition.2["pageOffsetX"] = locator.locations.position
        
        container?.updatedReadingPosition.0 = locator.locations.progression ?? 0.0
        container?.updatedReadingPosition.1 = locator.locations.totalProgression ?? 0.0
        
        container?.updatedReadingPosition.3 = locator.title ?? ""
    }
    
    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        let viewport = navigator.view.bounds
        // Skips to previous/next pages if the tap is on the content edges.
        let thresholdRange = 0...(0.2 * viewport.width)
        var moved = false
        if thresholdRange ~= point.x {
            moved = navigator.goLeft(animated: false)
        } else if thresholdRange ~= (viewport.maxX - point.x) {
            moved = navigator.goRight(animated: false)
        }
        
        if !moved {
            container?.toggleNavigationBar()
        }
    }
}
