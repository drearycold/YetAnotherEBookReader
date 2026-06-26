//
//  PDFOptionView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/3/16.
//

import SwiftUI

@MainActor
final class PDFOptionViewModel: ObservableObject {
    @Published var preferences: PDFPreferenceValue
    let onPreferencesChanged: (PDFPreferenceValue) -> Void

    init(
        preferences: PDFPreferenceValue,
        onPreferencesChanged: @escaping (PDFPreferenceValue) -> Void = { _ in }
    ) {
        self.preferences = preferences
        self.onPreferencesChanged = onPreferencesChanged
    }

    func commit() {
        onPreferencesChanged(preferences)
    }
}

struct PDFOptionView: View {
    @ObservedObject var model: PDFOptionViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Theme Mode")
                        Spacer()
                        Text("need reopen").font(.caption)
                    }
                    Picker(selection: $model.preferences.themeMode, label: Text("Theme Mode")) {
                        ForEach(PDFThemeMode.allCases, id: \.self) {
                            Image("icon-theme-\($0.rawValue)").tag($0)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Layout Mode")
                    Picker(selection: $model.preferences.pageMode, label: Text("Layout Mode")) {
                        ForEach(PDFLayoutMode.allCases, id: \.self) {
                            Text($0.id).tag($0)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                switch model.preferences.pageMode {
                case .Page:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reading Direction")
                        Picker(selection: $model.preferences.readingDirection, label: Text("Reading Direction")) {
                            ForEach(PDFReadDirection.allCases, id:\.self) {
                                Text($0.id).tag($0)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                case .Scroll:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scroll Direction")
                        Picker(selection: $model.preferences.scrollDirection, label: Text("Scroll Direction")) {
                            ForEach(PDFScrollDirection.allCases, id:\.self) {
                                Text($0.id).tag($0)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto Fit Visible Content")
                    Picker(selection: $model.preferences.selectedAutoScaler, label: Text("Auto Fit Page")) {
                        ForEach(PDFAutoScaler.allCases, id:\.self) { autoScaler in
                            Text(autoScaler.id).tag(autoScaler)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                HStack {
                    Toggle("Remember In-Page Position", isOn: $model.preferences.rememberInPagePosition)
                }
                
                Divider()
                
                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Top/Bottom Content Detect Strength")
                        Slider(value: $model.preferences.hMarginDetectStrength, in: 0...10, step: 1, minimumValueLabel: Text("Weak"), maximumValueLabel: Text("Strong")) {
                            Text("Top/Bottom Content Detect Strength")
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Left/Right Content Detect Strength")
                        Slider(value: $model.preferences.vMarginDetectStrength, in: 0...10, step: 1, minimumValueLabel: Text("Weak"), maximumValueLabel: Text("Strong")) {
                            Text("Left/Right Content Detect Strength")
                        }
                    }
                    
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Horizontal Margin")
                        Slider(value: $model.preferences.hMarginAutoScaler, in: 0...20, step: 1, minimumValueLabel: Text("0%"), maximumValueLabel: Text("20%")) {
                            Text("H Margin")
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vertical Margin")
                        Slider(value: $model.preferences.vMarginAutoScaler, in: 0...20, step: 1, minimumValueLabel: Text("0%"), maximumValueLabel: Text("20%")) {
                            Text("V Margin")
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Margin Offset")
                        Slider(value: $model.preferences.marginOffset, in: -10...10, step: 1, minimumValueLabel: Text("-10%"), maximumValueLabel: Text("10%")) {
                            Text("Margin Offset")
                        }
                    }
                }
            }
            .padding(10)
            .onChange(of: model.preferences.themeMode) { _ in handleOptionsChange() }
            .onChange(of: model.preferences.selectedAutoScaler) { _ in handleOptionsChange() }
            .onChange(of: model.preferences.pageMode) { _ in handleOptionsChange() }
            .onChange(of: model.preferences.readingDirection) { _ in handleOptionsChange() }
            .onChange(of: model.preferences.scrollDirection) { _ in handleOptionsChange() }
            .onChange(of: model.preferences.hMarginAutoScaler) { _ in handleOptionsChange() }
            .onChange(of: model.preferences.vMarginAutoScaler) { _ in handleOptionsChange() }
            .onChange(of: model.preferences.hMarginDetectStrength) { _ in handleOptionsChange() }
            .onChange(of: model.preferences.vMarginDetectStrength) { _ in handleOptionsChange() }
            .onChange(of: model.preferences.marginOffset) { _ in handleOptionsChange() }
            .onChange(of: model.preferences.rememberInPagePosition) { _ in handleOptionsChange() }
        }
    }
    
    private func handleOptionsChange() {
        model.commit()
    }
}

struct PDFOptionView_Previews: PreviewProvider {
    static var previews: some View {
        PDFOptionView(model: PDFOptionViewModel(preferences: PDFPreferenceValue()))
            .previewDevice(PreviewDevice(rawValue: "iPhone 7"))
    }
}
