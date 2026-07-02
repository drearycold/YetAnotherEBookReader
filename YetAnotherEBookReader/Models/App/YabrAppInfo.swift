//
//  YabrAppInfo.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2026/4/6.
//

import Foundation
import UIKit

struct YabrAppInfo {
    static let shared = YabrAppInfo()
    
    let infoPlist: NSDictionary?
    let yabrInfoPlist: NSDictionary?
    
    private init() {
        if let path = Bundle.main.path(forResource: "Info", ofType: "plist") {
            infoPlist = NSDictionary(contentsOfFile: path)
        } else {
            infoPlist = try? NSDictionary(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true).appendingPathComponent("Info.plist", isDirectory: false), error: ())
        }
        if let path = Bundle.main.path(forResource: "YabrInfo", ofType: "plist", inDirectory: "YabrResources") {
            yabrInfoPlist = NSDictionary(contentsOfFile: path)
        } else {
            yabrInfoPlist = nil
        }
    }
    
    var version: String {
        infoPlist?.value(forKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
    
    var build: String {
        infoPlist?.value(forKey: "CFBundleVersion") as? String ?? "1"
    }
    
    var gadBannerShelfUnitID: String? {
        #if DEBUG
        yabrInfoPlist?.value(forKey: "GADBannerShelfUnitIDTest") as? String
        #else
        yabrInfoPlist?.value(forKey: "GADBannerShelfUnitID") as? String
        #endif
    }
    
    var gadDeviceIdentifierTest: String? {
        yabrInfoPlist?.value(forKey: "GADDeviceIdentifierTest") as? String
    }
    
    var baseUrl: URL? {
        guard let value = yabrInfoPlist?.value(forKey: "YABRBaseURL") as? String
        else { return nil }
        
        return URL(string: value)
    }
    
    var newIssueUrl: String? {
        yabrInfoPlist?.value(forKey: "YABRNewIssueURL") as? String
    }
    
    var newEnhancementUrl: String? {
        yabrInfoPlist?.value(forKey: "YABRNewEnhancementURL") as? String
    }
    
    var privacyHtml: String? {
        guard let path = Bundle.main.path(forResource: "Privacy", ofType: "html", inDirectory: "YabrResources")
        else { return nil }
        return try? String(contentsOfFile: path)
    }
    
    var termsHtml: String? {
        guard let path = Bundle.main.path(forResource: "Terms", ofType: "html", inDirectory: "YabrResources")
        else { return nil }
        return try? String(contentsOfFile: path)
    }
    
    var versionHtml: String? {
        guard let path = Bundle.main.path(forResource: "Version", ofType: "html", inDirectory: "YabrResources")
        else { return nil }
        return try? String(contentsOfFile: path)
    }
}
