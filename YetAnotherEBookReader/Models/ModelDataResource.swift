//
//  ModelDataResource.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/1/15.
//

import Foundation

extension ModelData {
    var yarbVersion: String {
        self.resourceFileDictionary?.value(forKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
    
    var yabrBuild: String {
        self.resourceFileDictionary?.value(forKey: "CFBundleVersion") as? String ?? "1"
    }
    
    var yabrGADBannerShelfUnitID: String? {
        #if DEBUG
        self.yabrResourceFileDictionary?.value(forKey: "GADBannerShelfUnitIDTest") as? String
        #else
        self.yabrResourceFileDictionary?.value(forKey: "GADBannerShelfUnitID") as? String
        #endif
    }
    
    var yabrGADDeviceIdentifierTest: String? {
        self.yabrResourceFileDictionary?.value(forKey: "GADDeviceIdentifierTest") as? String
    }
    
    var yabrBaseUrl: URL? {
        guard let value = self.yabrResourceFileDictionary?.value(forKey: "YABRBaseURL") as? String
        else { return nil }
        
        return URL(string: value)
    }
    
    var yabrNewIssueUrl: String? {
        self.yabrResourceFileDictionary?.value(forKey: "YABRNewIssueURL") as? String
    }
    
    var yabrNewEnhancementUrl: String? {
        self.yabrResourceFileDictionary?.value(forKey: "YABRNewEnhancementURL") as? String
    }
    
    var yabrPrivacyHtml: String? {
        guard let path = Bundle.main.path(forResource: "Privacy", ofType: "html", inDirectory: "YabrResources")
        else { return nil }
        return try? String(contentsOfFile: path)
    }
    
    var yabrTermsHtml: String? {
        guard let path = Bundle.main.path(forResource: "Terms", ofType: "html", inDirectory: "YabrResources")
        else { return nil }
        return try? String(contentsOfFile: path)
    }
    
    var yabrVersionHtml: String? {
        guard let path = Bundle.main.path(forResource: "Version", ofType: "html", inDirectory: "YabrResources")
        else { return nil }
        return try? String(contentsOfFile: path)
    }
}
