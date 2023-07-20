//
//  YabrPDFSharingProvider.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/7/20.
//

import Foundation
import UIKit

class YabrPDFSharingProvider: UIActivityItemProvider {
    var subject: String = ""
    var fileURL: URL?
    
//    override var item: Any {
//        if let fileURL = fileURL {
//            return fileURL
//        } else {
//            return ""
//        }
//    }
    
//    override var activityType: UIActivity.ActivityType? {
//        return nil
//    }
    
    override init(placeholderItem: Any) {
        super.init(placeholderItem: placeholderItem)
    }
    
    override func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return subject
    }
    
    override func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return fileURL
    }
}
