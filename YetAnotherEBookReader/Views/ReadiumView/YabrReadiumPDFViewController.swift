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
import RealmSwift

import ReadiumAdapterGCDWebServer

final class YabrReadiumPDFViewController: YabrReadiumReaderViewController {
    
    init?(publication: Publication, initialLocation: Locator?, environment: YabrReadiumEnvironment) {
        guard let navigator = try? PDFNavigatorViewController(publication: publication, initialLocation: initialLocation, httpServer: environment.httpServer) else {
            return nil
        }
        
        super.init(navigator: navigator, publication: publication, initialLocation: initialLocation, environment: environment)
        
        navigator.delegate = self
    }
    
    var pdfNavigator: PDFNavigatorViewController {
        return navigator as! PDFNavigatorViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func applyPreferences(_ prefs: ReadiumPreferenceRealm) {
        pdfNavigator.submitPreferences(prefs.toPDFPreferences())
    }
    
    override func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
        let isScroll = self.pdfNavigator.settings.scroll
        
        if isScroll {
            return nil
        }
        
        let safeArea = self.view.window?.safeAreaInsets ?? self.view.safeAreaInsets
        let additional = self.navigator.additionalSafeAreaInsets
        
        let inset = UIEdgeInsets(
            top: safeArea.top + additional.top,
            left: safeArea.left + additional.left,
            bottom: safeArea.bottom + additional.bottom,
            right: safeArea.right + additional.right
        )
        self.log(.debug, "navigatorContentInset called, additionalTop=\(additional.top), returning: \(inset)")
        return inset
    }
}
