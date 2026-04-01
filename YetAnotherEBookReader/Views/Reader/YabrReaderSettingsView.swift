//
//  YabrReaderSettingsView.swift
//  YetAnotherEBookReader
//
//  Created by Gemini CLI on 2024/03/26.
//

import SwiftUI
import RealmSwift

struct YabrReaderSettingsView: View {
    @ObservedRealmObject var prefs: ReadiumPreferenceRealm
    
    let supportedFontFamilies: [String] = [
        "Original",
        "serif",
        "sans-serif",
        "monospace",
        "IA Writer Duospace",
        "AccessibleDfA",
        "OpenDyslexic",
        "Iowan Old Style",
        "Palatino"
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $prefs.themeMode) {
                        Text("Light").tag(0)
                        Text("Sepia").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if prefs.themeMode == 2 { // Dark mode
                        Picker("Image Filter", selection: $prefs.imageFilter) {
                            Text("None").tag(0)
                            Text("Darken").tag(1)
                            Text("Invert").tag(2)
                        }
                    }
                    
                    Toggle("Scroll Mode", isOn: $prefs.scroll)
                    
                    if !prefs.scroll {
                        Picker("Columns", selection: $prefs.columnCount) {
                            Text("Auto").tag(0)
                            Text("1").tag(1)
                            Text("2").tag(2)
                        }
                    }
                }
                
                Section(header: Text("Typography")) {
                    Picker("Typeface", selection: $prefs.fontFamily) {
                        ForEach(supportedFontFamilies, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    
                    HStack {
                        Button(action: { 
                            if prefs.fontSizePercentage > 50 { 
                                $prefs.fontSizePercentage.wrappedValue -= 10 
                            } 
                        }) {
                            Image(systemName: "textformat.size.smaller")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        Spacer()
                        Text("Font Size: \(Int(prefs.fontSizePercentage))%")
                            .font(.subheadline)
                        Spacer()
                        Button(action: { 
                            if prefs.fontSizePercentage < 300 { 
                                $prefs.fontSizePercentage.wrappedValue += 10 
                            } 
                        }) {
                            Image(systemName: "textformat.size.larger")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    
                    Stepper(value: $prefs.fontWeight, in: 0.0...2.5, step: 0.25) {
                        Text("Font Weight: \(prefs.fontWeight, specifier: "%.2f")")
                    }
                    
                    Toggle("Text Normalization", isOn: $prefs.textNormalization)
                }
                
                Section(header: Text("Layout")) {
                    Toggle("Publisher Styles", isOn: $prefs.publisherStyles)
                    
                    if !prefs.publisherStyles {
                        Group {
                            Picker("Alignment", selection: $prefs.textAlign) {
                                Text("Default").tag(0)
                                Text("Start").tag(1)
                                Text("Left").tag(2)
                                Text("Right").tag(3)
                                Text("Justify").tag(4)
                            }
                            
                            Stepper(value: $prefs.lineHeight, in: 1.0...2.0, step: 0.1) {
                                Text("Line Height: \(prefs.lineHeight, specifier: "%.1f")")
                            }
                            
                            Stepper(value: $prefs.typeScale, in: 1.0...2.0, step: 0.1) {
                                Text("Type Scale: \(prefs.typeScale, specifier: "%.1f")")
                            }
                            
                            Stepper(value: $prefs.wordSpacing, in: 0.0...1.0, step: 0.1) {
                                Text("Word Spacing: \(prefs.wordSpacing, specifier: "%.1f")")
                            }
                            
                            Stepper(value: $prefs.letterSpacing, in: 0.0...1.0, step: 0.1) {
                                Text("Letter Spacing: \(prefs.letterSpacing, specifier: "%.1f")")
                            }
                            
                            Stepper(value: $prefs.paragraphIndent, in: 0.0...3.0, step: 0.2) {
                                Text("Paragraph Indent: \(prefs.paragraphIndent, specifier: "%.1f")")
                            }
                            
                            Stepper(value: $prefs.paragraphSpacing, in: 0.0...2.0, step: 0.1) {
                                Text("Paragraph Spacing: \(prefs.paragraphSpacing, specifier: "%.1f")")
                            }
                            
                            Toggle("Hyphens", isOn: $prefs.hyphens)
                        }
                    }
                    
                    Stepper(value: $prefs.pageMargins, in: 0.0...4.0, step: 0.3) {
                        Text("Page Margins: \(prefs.pageMargins, specifier: "%.1f")")
                    }
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(minWidth: 320, minHeight: 500)
    }
}
