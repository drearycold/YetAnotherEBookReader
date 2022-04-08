//
//  PDFOptionView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/3/16.
//

import SwiftUI

enum PDFAutoScaler: String, CaseIterable, Identifiable {
    case Custom
    case Width
    case Height
    case Page
    
    var id: String { self.rawValue }
}

enum PDFReadDirection: String, CaseIterable, Identifiable {
    case LtR_TtB
    case TtB_RtL
    
    var id: String { self.rawValue }
}

enum PDFThemeMode: String, CaseIterable, Identifiable {
    case none
    case serpia
    case forest
    case dark
    
    var id: String { self.rawValue }
}

struct PDFOptions: Equatable {
    var themeMode = PDFThemeMode.serpia
    var selectedAutoScaler = PDFAutoScaler.Width
    var readingDirection = PDFReadDirection.LtR_TtB
    var hMarginAutoScaler = CGFloat(5.0)
    var vMarginAutoScaler = CGFloat(5.0)
    var hMarginDetectStrength = CGFloat(2.0)
    var vMarginDetectStrength = CGFloat(2.0)
    var lastScale = CGFloat(-1.0)
    var rememberInPagePosition = true
}

struct PDFOptionView: View {
    var pdfViewController: YabrPDFViewController?
    
    @State private var pdfOptions = PDFOptions()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button(action: {}, label: {
                        Image(systemName: "questionmark.circle")
                    })
                }.hidden()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Theme Mode")
                        Spacer()
                        Text("need reopen").font(.caption)
                    }
                    Picker(selection: $pdfOptions.themeMode, label: Text("Theme Mode")) {
                        ForEach(PDFThemeMode.allCases, id: \.self) { themeMode in
                            Image("icon-theme-\(themeMode.rawValue)").tag(themeMode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reading Direction")
                    Picker(selection: $pdfOptions.readingDirection, label: Text("Reading Direction")) {
                        ForEach(PDFReadDirection.allCases, id:\.self) { readingDirection in
                            Text(readingDirection.id).tag(readingDirection)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto Fit Visible Content")
                    Picker(selection: $pdfOptions.selectedAutoScaler, label: Text("Auto Fit Page")) {
                        ForEach(PDFAutoScaler.allCases, id:\.self) { autoScaler in
                            Text(autoScaler.id).tag(autoScaler)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                
                HStack {
                    Toggle("Remember In-Page Position", isOn: $pdfOptions.rememberInPagePosition)
                }
                
                Divider()
                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Top/Bottom Content Detect Strength")
                        Slider(value: $pdfOptions.hMarginDetectStrength, in: 0...10, step: 1, minimumValueLabel: Text("Weak"), maximumValueLabel: Text("Strong")) {
                            Text("Top/Bottom Content Detect Strength")
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Left/Right Content Detect Strength")
                        Slider(value: $pdfOptions.vMarginDetectStrength, in: 0...10, step: 1, minimumValueLabel: Text("Weak"), maximumValueLabel: Text("Strong")) {
                            Text("Left/Right Content Detect Strength")
                        }
                    }
                }
                Divider()

                Group {

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Horizontal Margin")
                        Slider(value: $pdfOptions.hMarginAutoScaler, in: 0...20, step: 1, minimumValueLabel: Text("0%"), maximumValueLabel: Text("20%")) {
                            Text("H Margin")
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vertical Margin")
                        Slider(value: $pdfOptions.vMarginAutoScaler, in: 0...20, step: 1, minimumValueLabel: Text("0%"), maximumValueLabel: Text("20%")) {
                            Text("V Margin")
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            .onAppear() {
                if self.pdfViewController != nil {
                    self.pdfOptions = self.pdfViewController!.pdfOptions
                }
            }
            .onChange(of: pdfOptions) {_ in
                self.pdfViewController!.handleOptionsChange(pdfOptions: self.pdfOptions)
            }
        }
    }
}

struct PDFOptionView_Previews: PreviewProvider {
    static var previews: some View {
        PDFOptionView(pdfViewController: nil).previewDevice(PreviewDevice(rawValue: "iPhone 7"))
    }
}
