//
//  FontsManager.swift
//  YetAnotherEBookReader
//
//  Created by Gemini on 2026/4/6.
//

import Foundation
import CoreText
import SwiftUI

class FontsManager: ObservableObject {
    @Published var userFontInfos = [String: FontInfo]()
    
    init() {
        reloadCustomFonts()
    }
    
    func importCustomFonts(urls: [URL]) -> [CFArray]? {
        guard let documentDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return nil }
        
        let fontsDirectory = documentDirectory.appendingPathComponent("Fonts",  isDirectory: true)
        guard let _ = try? FileManager.default.createDirectory(atPath: fontsDirectory.path, withIntermediateDirectories: true, attributes: nil) else { return nil }
    
        var fontDescriptorArrays = [CFArray]()

        urls.forEach { url in
            guard let ctFontDescriptorArray = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
            else { return }
            
            let fontDestFile = fontsDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: fontDestFile.path) {
                    try FileManager.default.removeItem(at: fontDestFile)
                }
                try FileManager.default.moveItem(atPath: url.path, toPath: fontDestFile.path)
                fontDescriptorArrays.append(ctFontDescriptorArray)
            } catch {
                print("importCustomFonts \(error.localizedDescription)")
            }
        }
        
        return fontDescriptorArrays
    }
    
    func removeCustomFonts(at offsets: IndexSet) {
        let list = userFontInfos.sorted {
            ( $0.value.displayName ?? $0.key) < ( $1.value.displayName ?? $1.key)
        }
        let candidates = offsets.map { list[$0] }
        candidates.forEach { (fontId, fontInfo) in
            guard let fileURL = fontInfo.fileURL else { return }
            try? FileManager.default.removeItem(atPath: fileURL.path)
        }
    }
    
    func reloadCustomFonts() {
        if let userFontDescriptors = loadUserFonts() {
            self.userFontInfos = userFontDescriptors.mapValues { FontInfo(descriptor: $0) }
        } else {
            self.userFontInfos.removeAll()
        }
    }
}

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
