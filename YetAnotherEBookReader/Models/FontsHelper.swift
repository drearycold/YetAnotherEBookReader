//
//  FontsHelper.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/12.
//

import Foundation
import CoreText

func loadUserFonts() -> [String: CTFontDescriptor]? {
    guard let documentDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    else { return nil }
    
    let fontsDirectory = documentDirectory.appendingPathComponent("Fonts",  isDirectory: true)
    guard let _ = try? FileManager.default.createDirectory(atPath: fontsDirectory.path, withIntermediateDirectories: true, attributes: nil),
          let fontsEnumerator = FileManager.default.enumerator(atPath: fontsDirectory.path) else { return nil }
    
    var userFontDescriptors = [String: CTFontDescriptor]()
    while let file = fontsEnumerator.nextObject() as? String {
        print("FONTDIR \(file)")
        let fileURL = fontsDirectory.appendingPathComponent(file)
        
        if let ctFontDescriptorArray = CTFontManagerCreateFontDescriptorsFromURL(fileURL as CFURL) {
            CTFontManagerRegisterFontDescriptors(ctFontDescriptorArray, .process, true) { errors, done -> Bool in
                return true
            }
            
            let count = CFArrayGetCount(ctFontDescriptorArray)
            for i in 0..<count {
                let valuePointer = CFArrayGetValueAtIndex(ctFontDescriptorArray, CFIndex(i))
                let ctFontDescriptor = unsafeBitCast(valuePointer, to: CTFontDescriptor.self)
                let ctFontName = unsafeBitCast(CTFontDescriptorCopyAttribute(ctFontDescriptor, kCTFontNameAttribute), to: CFString.self)
                print("CTFONT \(ctFontName) \(fileURL)")
                userFontDescriptors[ctFontName as String] = ctFontDescriptor
            }
        }
    }
    return userFontDescriptors
}
