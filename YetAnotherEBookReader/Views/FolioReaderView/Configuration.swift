//
//  Configuration.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/9/27.
//

import Foundation
import UIKit
import FolioReaderKit

enum UITestingConfiguration {
    static let mockLibraryArgument = "--ui-testing-mock-library"
    static let mockReaderType = ReaderType.YabrEPUB
    static let mockFolioReaderScrollDirection = FolioReaderScrollDirection.horizontalWithPagedContent
    static let mockEPUBResourceName = "UI Test Fixture"

    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(mockLibraryArgument)
    }

    static func folioReaderCloseButtonEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        isEnabled(arguments: arguments)
    }

    static func mockFolioReaderPreferences() -> FolioReaderPreferenceValue {
        var preferences = FolioReaderPreferenceValue.fallbackDefaults
        preferences.currentScrollDirection = mockFolioReaderScrollDirection.rawValue
        return preferences
    }
}

extension EpubFolioReaderContainer {
    static func Configuration(
        bookURL: URL,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> FolioReaderConfig {
        let isUITestingMockLibrary = UITestingConfiguration.isEnabled(arguments: arguments)
        let config = FolioReaderConfig(withIdentifier: bookURL.deletingPathExtension().lastPathComponent)
        config.shouldHideNavigationOnTap = true
        config.canChangeScrollDirection = !isUITestingMockLibrary
        if isUITestingMockLibrary {
            config.scrollDirection = UITestingConfiguration.mockFolioReaderScrollDirection
        }
        config.allowSharing = true
        config.enableTTS = false
        config.displayTitle = UITraitCollection.current.horizontalSizeClass == .regular
        config.showCloseButton = UITestingConfiguration.folioReaderCloseButtonEnabled(arguments: arguments)
        config.forceBottomMenuTabBar = true
        config.reserveSafeAreaInsidePageFrame = false
        config.reservePageIndicatorInsidePageFrame = false
        //config.localizedShareWebLink = URL(string: "yabr://share.book/")
        
        #if DEBUG
        config.debug = []
        //config.debug.formUnion([.borderHighlight])
        //config.debug.formUnion([.viewTransition])
        //config.debug.formUnion([.functionTrace])
        //config.debug.formUnion([.htmlStyling, .borderHighlight])
        //config.debug.formUnion([.htmlStyling])
        #endif
        // See more at FolioReaderConfig.swift
    //        config.canChangeScrollDirection = false
    //        config.enableTTS = false
    //        config.displayTitle = true
    //        config.allowSharing = false
    //        config.tintColor = UIColor.blueColor()
    //        config.toolBarTintColor = UIColor.redColor()
    //        config.toolBarBackgroundColor = UIColor.purpleColor()
    //        config.menuTextColor = UIColor.brownColor()
    //        config.menuBackgroundColor = UIColor.lightGrayColor()
    //        config.hidePageIndicator = true
    //        config.realmConfiguration = Realm.Configuration(fileURL: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("highlights.realm"))

        // Custom sharing quote background
        config.quoteCustomBackgrounds = []
        if let image = UIImage(named: "demo-bg") {
            let customImageQuote = QuoteImage(withImage: image, alpha: 0.6, backgroundColor: UIColor.black)
            config.quoteCustomBackgrounds.append(customImageQuote)
        }

        let textColor = UIColor(red:0.86, green:0.73, blue:0.70, alpha:1.0)
        let customColor = UIColor(red:0.30, green:0.26, blue:0.20, alpha:1.0)
        let customQuote = QuoteImage(withColor: customColor, alpha: 1.0, textColor: textColor)
        config.quoteCustomBackgrounds.append(customQuote)

        return config
    }

}
