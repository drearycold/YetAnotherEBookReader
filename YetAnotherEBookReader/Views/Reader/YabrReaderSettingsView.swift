//
//  YabrReaderSettingsView.swift
//  YetAnotherEBookReader
//
//  Created by Gemini CLI on 2024/03/26.
//

import SwiftUI

struct YabrReaderSettingsView: View {
    @ObservedObject var viewModel: YabrReaderSettingsViewModel
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $viewModel.themeMode) {
                        Text("Light").tag(0)
                        Text("Sepia").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if viewModel.themeMode == 2 { // Dark mode
                        Picker("Image Filter", selection: $viewModel.imageFilter) {
                            Text("None").tag(0)
                            Text("Darken").tag(1)
                            Text("Invert").tag(2)
                        }
                    }
                    
                    Toggle("Scroll Mode", isOn: $viewModel.scroll)
                    
                    if !viewModel.scroll {
                        Picker("Columns", selection: $viewModel.columnCount) {
                            Text("Auto").tag(0)
                            Text("1").tag(1)
                            Text("2").tag(2)
                        }
                    }
                }
                
                Section(header: Text("Typography")) {
                    Picker("Typeface", selection: $viewModel.fontFamily) {
                        ForEach(viewModel.supportedFontFamilies, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    
                    HStack {
                        Button(action: { if viewModel.fontSizePercentage > 50 { viewModel.fontSizePercentage -= 10 } }) {
                            Image(systemName: "textformat.size.smaller")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        Spacer()
                        Text("Font Size: \(Int(viewModel.fontSizePercentage))%")
                            .font(.subheadline)
                        Spacer()
                        Button(action: { if viewModel.fontSizePercentage < 300 { viewModel.fontSizePercentage += 10 } }) {
                            Image(systemName: "textformat.size.larger")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    
                    Stepper(value: $viewModel.fontWeight, in: 0.0...2.5, step: 0.25) {
                        Text("Font Weight: \(viewModel.fontWeight, specifier: "%.2f")")
                    }
                    
                    Toggle("Text Normalization", isOn: $viewModel.textNormalization)
                }
                
                Section(header: Text("Layout")) {
                    Toggle("Publisher Styles", isOn: $viewModel.publisherStyles)
                    
                    if !viewModel.publisherStyles {
                        Group {
                            Picker("Alignment", selection: $viewModel.textAlign) {
                                Text("Default").tag(0)
                                Text("Start").tag(1)
                                Text("Left").tag(2)
                                Text("Right").tag(3)
                                Text("Justify").tag(4)
                            }
                            
                            Stepper(value: $viewModel.lineHeight, in: 1.0...2.0, step: 0.1) {
                                Text("Line Height: \(viewModel.lineHeight, specifier: "%.1f")")
                            }
                            
                            Stepper(value: $viewModel.typeScale, in: 1.0...2.0, step: 0.1) {
                                Text("Type Scale: \(viewModel.typeScale, specifier: "%.1f")")
                            }
                            
                            Stepper(value: $viewModel.wordSpacing, in: 0.0...1.0, step: 0.1) {
                                Text("Word Spacing: \(viewModel.wordSpacing, specifier: "%.1f")")
                            }
                            
                            Stepper(value: $viewModel.letterSpacing, in: 0.0...1.0, step: 0.1) {
                                Text("Letter Spacing: \(viewModel.letterSpacing, specifier: "%.1f")")
                            }
                            
                            Stepper(value: $viewModel.paragraphIndent, in: 0.0...3.0, step: 0.2) {
                                Text("Paragraph Indent: \(viewModel.paragraphIndent, specifier: "%.1f")")
                            }
                            
                            Stepper(value: $viewModel.paragraphSpacing, in: 0.0...2.0, step: 0.1) {
                                Text("Paragraph Spacing: \(viewModel.paragraphSpacing, specifier: "%.1f")")
                            }
                            
                            Toggle("Hyphens", isOn: $viewModel.hyphens)
                        }
                    }
                    
                    Stepper(value: $viewModel.pageMargins, in: 0.0...4.0, step: 0.3) {
                        Text("Page Margins: \(viewModel.pageMargins, specifier: "%.1f")")
                    }
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(minWidth: 320, minHeight: 500)
    }
}

struct YabrReaderSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        YabrReaderSettingsView(viewModel: YabrReaderSettingsViewModel(engineType: .readium))
    }
}
