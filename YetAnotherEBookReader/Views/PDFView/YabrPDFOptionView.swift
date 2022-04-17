//
//  PDFOptionView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/3/16.
//

import SwiftUI

struct PDFOptionView: View {
    @Binding var pdfViewController: YabrPDFViewController
    
    @State private var pdfOptions = PDFOptions()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Theme Mode")
                        Spacer()
                        Text("need reopen").font(.caption)
                    }
                    Picker(selection: $pdfOptions.themeMode, label: Text("Theme Mode")) {
                        ForEach(PDFThemeMode.allCases, id: \.self) {
                            Image("icon-theme-\($0.rawValue)").tag($0)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reading Direction")
                    Picker(selection: $pdfOptions.readingDirection, label: Text("Reading Direction")) {
                        ForEach(PDFReadDirection.allCases, id:\.self) {
                            Text($0.id).tag($0)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Layout Mode")
                    Picker(selection: $pdfOptions.pageMode, label: Text("Layout Mode")) {
                        ForEach(PDFLayoutMode.allCases, id: \.self) {
                            Text($0.id).tag($0)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto Fit Visible Content")
                    Picker(selection: $pdfOptions.selectedAutoScaler, label: Text("Auto Fit Page")) {
                        ForEach(PDFAutoScaler.allCases, id:\.self) { autoScaler in
                            Text(autoScaler.id).tag(autoScaler)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
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
            .padding(10)
            .onAppear() {
                    self.pdfOptions = self.pdfViewController.pdfOptions
            }
            .onChange(of: pdfOptions) {_ in
                self.pdfViewController.handleOptionsChange(pdfOptions: self.pdfOptions)
            }
        }
    }
}

struct PDFOptionView_Previews: PreviewProvider {
    @State static var pdfViewController = YabrPDFViewController()
    
    static var previews: some View {
        PDFOptionView(pdfViewController: $pdfViewController).previewDevice(PreviewDevice(rawValue: "iPhone 7"))
    }
}
