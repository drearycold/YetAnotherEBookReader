//
//  PDFPageWithBackground.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/9/10.
//

import Foundation
import PDFKit

class PDFPageWithBackground : PDFPage {
    static var fillColor: CGColor? = nil   //defaults to serpia
    static let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        // Draw original content
        super.draw(with: box, to: context)
        
        
        guard let fillColor = PDFPageWithBackground.fillColor,
            let fillColorDeviceRGB = fillColor.converted(to: PDFPageWithBackground.colorSpace, intent: .defaultIntent, options: nil) else { return }
        
        let grayComponents = fillColor.converted(to: CGColorSpace(name: CGColorSpace.linearGray)!, intent: .defaultIntent, options: nil)?.components ?? []
        print("\(#function) draw gray \(grayComponents)")
        
        let rect = self.bounds(for: box)

        if grayComponents.count > 1, grayComponents[0] < 0.3 {
            UIGraphicsPushContext(context)
            context.saveGState()
            
            context.setBlendMode(.exclusion)
            context.setFillColor(gray: 1.0 - grayComponents[0], alpha: 1.0)
            context.fill(rect.offsetBy(dx: -rect.minX, dy: -rect.minY))
            
            context.setBlendMode(.darken)
            context.setFillColor(gray: 0.7, alpha: 1.0)
            context.fill(rect.offsetBy(dx: -rect.minX, dy: -rect.minY))

            context.restoreGState()
            UIGraphicsPopContext()
        } else {
            UIGraphicsPushContext(context)
            context.saveGState()
            context.setBlendMode(.darken)
            context.setFillColor(fillColorDeviceRGB)
            context.fill(rect.offsetBy(dx: -rect.minX, dy: -rect.minY))
            context.restoreGState()
            UIGraphicsPopContext()
        }
        // print("context \(box.rawValue) \(context.height) \(context.width)")
    }
    
    func thumbnailWithBackground(of size: CGSize, for box: PDFDisplayBox) -> UIImage {
        let image = super.thumbnail(of: size, for: box)
        
        guard let fillColor = PDFPageWithBackground.fillColor,
            let fillColorDeviceRGB = fillColor.converted(to: PDFPageWithBackground.colorSpace, intent: .defaultIntent, options: nil) else { return image }
        
        let grayComponents = fillColor.converted(to: CGColorSpace(name: CGColorSpace.linearGray)!, intent: .defaultIntent, options: nil)?.components ?? []
        print("\(#function) draw gray \(grayComponents)")
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        defer {
            UIGraphicsEndImageContext()
        }

        let rect = CGRect(origin: .zero, size: image.size)
        image.draw(in: rect)

        if grayComponents.count > 1, grayComponents[0] < 0.3 {
            context.setBlendMode(.exclusion)
            context.setFillColor(gray: 1.0 - grayComponents[0], alpha: 1.0)
            context.fill(rect)
            
            context.setBlendMode(.darken)
            context.setFillColor(gray: 0.7, alpha: 1.0)
            context.fill(rect)
        } else {
            context.setBlendMode(.darken)
            context.setFillColor(fillColorDeviceRGB)
            context.fill(rect)
        }
        guard let coloredImg = UIGraphicsGetImageFromCurrentImageContext() else { return image }
        
        return coloredImg
    }
    
    override func thumbnail(of size: CGSize, for box: PDFDisplayBox) -> UIImage {
        let uiImage = super.thumbnail(of: size, for: box)
        
        print("\(#function) size=\(size) box=\(box)")
        
        return uiImage
    }
}
