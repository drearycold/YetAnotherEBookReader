//
//  Configuration.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/9/27.
//

import Foundation
import FolioReaderKit

extension EpubFolioReaderContainer {
    static func Configuration(bookURL: URL) -> FolioReaderConfig {
        let config = FolioReaderConfig(withIdentifier: bookURL.lastPathComponent)
        config.shouldHideNavigationOnTap = false
        config.scrollDirection = FolioReaderScrollDirection.vertical
        config.allowSharing = true
        config.displayTitle = true
        
        #if DEBUG
    //    config.debug.formUnion([.borderHighlight])
        config.debug.formUnion([.viewTransition])
        config.debug.formUnion([.functionTrace])
        //config.debug.formUnion([.htmlStyling, .borderHighlight])
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
