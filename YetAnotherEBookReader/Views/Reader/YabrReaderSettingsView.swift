import SwiftUI
import RealmSwift
import ReadiumShared
import ReadiumNavigator

class YabrReaderSettingsViewModel: ObservableObject {
    @Published var epubEditor: EPUBPreferencesEditor?
    @Published var pdfEditor: PDFPreferencesEditor?
    
    let prefs: ReadiumPreferenceRealm
    let publication: Publication
    let navigator: Navigator
    
    var onChanged: (() -> Void)?
    
    init(prefs: ReadiumPreferenceRealm, publication: Publication, navigator: Navigator) {
        self.prefs = prefs
        self.publication = publication
        self.navigator = navigator
        
        if let epub = navigator as? EPUBNavigatorViewController {
            self.epubEditor = EPUBPreferencesEditor(
                initialPreferences: prefs.toEPUBPreferences(),
                metadata: publication.metadata,
                defaults: EPUBDefaults()
            )
        } else if let pdf = navigator as? PDFNavigatorViewController {
            self.pdfEditor = PDFPreferencesEditor(
                initialPreferences: prefs.toPDFPreferences(),
                metadata: publication.metadata,
                defaults: PDFDefaults()
            )
        }
    }
    
    func commit() {
        let updateAction = { [weak self] in
            guard let self = self else { return }
            if let epubEditor = self.epubEditor {
                self.prefs.update(from: epubEditor.preferences)
            } else if let pdfEditor = self.pdfEditor {
                self.prefs.update(from: pdfEditor.preferences)
            }
        }
        
        if let realm = prefs.realm {
            try? realm.write { updateAction() }
        } else {
            updateAction()
        }
        
        // Decouple navigator UI update from Realm write lock
        if let epubEditor = epubEditor {
            (navigator as? EPUBNavigatorViewController)?.submitPreferences(epubEditor.preferences)
        } else if let pdfEditor = pdfEditor {
            (navigator as? PDFNavigatorViewController)?.submitPreferences(pdfEditor.preferences)
        }
        
        onChanged?()
        objectWillChange.send()
    }
    
    func updateVerticalMargin(_ value: Double) {
        let updateAction = { [weak self] in
            self?.prefs.verticalMargin = value
        }
        
        if let realm = prefs.realm {
            try? realm.write { updateAction() }
        } else {
            updateAction()
        }
        
        (navigator as? UIViewController)?.additionalSafeAreaInsets = UIEdgeInsets(top: value, left: 0, bottom: value, right: 0)
        
        onChanged?()
        objectWillChange.send()
    }
}

extension Preference {
    func binding(onSet: @escaping () -> Void = {}) -> Binding<Value> {
        Binding(
            get: { value ?? effectiveValue },
            set: { set($0); onSet() }
        )
    }
    
    func optionalBinding(onSet: @escaping () -> Void = {}) -> Binding<Value?> {
        Binding(
            get: { value },
            set: { set($0); onSet() }
        )
    }
}

struct YabrReaderSettingsView: View {
    @ObservedObject var model: YabrReaderSettingsViewModel
    
    let supportedFontFamilies: [FontFamily] = [
        .serif,
        .sansSerif,
        .monospace,
        .iaWriterDuospace,
        .accessibleDfA,
        .openDyslexic,
        .iowanOldStyle,
        .palatino,
        .athelas,
        .georgia,
        .helveticaNeue,
        .seravek,
        .arial
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: Binding(
                        get: { model.prefs.themeMode },
                        set: { value in
                            if let realm = model.prefs.realm {
                                try? realm.write {
                                    model.prefs.themeMode = value
                                }
                            } else {
                                model.prefs.themeMode = value
                            }
                            
                            // Sync with Readium editor if available
                            if let editor = model.epubEditor {
                                switch value {
                                case 1: editor.theme.set(.sepia)
                                case 2: editor.theme.set(.dark)
                                default: editor.theme.set(.light)
                                }
                            }
                            model.commit()
                        }
                    )) {
                        Text("Light").tag(0)
                        Text("Sepia").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if let editor = model.epubEditor, editor.imageFilter.isEffective {
                        Picker("Image Filter", selection: editor.imageFilter.optionalBinding(onSet: {
                            model.commit()
                        })) {
                            Text("None").tag(nil as ImageFilter?)
                            Text("Darken").tag(ImageFilter.darken as ImageFilter?)
                            Text("Invert").tag(ImageFilter.invert as ImageFilter?)
                        }
                    }
                    
                    Toggle("Scroll Mode", isOn: Binding(
                        get: { model.prefs.scroll },
                        set: { value in
                            if let realm = model.prefs.realm {
                                try? realm.write {
                                    model.prefs.scroll = value
                                }
                            } else {
                                model.prefs.scroll = value
                            }
                            
                            // Sync with Readium editor
                            if let editor = model.epubEditor {
                                editor.scroll.set(value)
                            } else if let editor = model.pdfEditor {
                                editor.scroll.set(value)
                            }
                            
                            // Reset or apply vertical margin insets based on scroll mode
                            if value {
                                (model.navigator as? UIViewController)?.additionalSafeAreaInsets = .zero
                            } else {
                                let margin = model.prefs.verticalMargin
                                (model.navigator as? UIViewController)?.additionalSafeAreaInsets = UIEdgeInsets(top: margin, left: 0, bottom: margin, right: 0)
                            }
                            
                            model.commit()
                        }
                    ))
                    
                    Toggle("Volume Key Paging", isOn: Binding(
                        get: { model.prefs.volumeKeyPaging },
                        set: { value in
                            if let realm = model.prefs.realm {
                                try? realm.write {
                                    model.prefs.volumeKeyPaging = value
                                }
                            } else {
                                model.prefs.volumeKeyPaging = value
                            }
                            model.commit()
                        }
                    ))
                    
                    Picker("Progression", selection: Binding(
                        get: { model.prefs.readingProgression },
                        set: { value in
                            if let realm = model.prefs.realm {
                                try? realm.write {
                                    model.prefs.readingProgression = value
                                }
                            } else {
                                model.prefs.readingProgression = value
                            }
                            
                            let direction: ReadiumNavigator.ReadingProgression = (value == 1) ? .rtl : .ltr
                            if let editor = model.epubEditor {
                                editor.readingProgression.set(direction)
                            } else if let editor = model.pdfEditor {
                                editor.readingProgression.set(direction)
                            }
                            model.commit()
                        }
                    )) {
                        Text("LTR").tag(0)
                        Text("RTL").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if let editor = model.epubEditor {
                        if editor.columnCount.isEffective {
                            Picker("Columns", selection: editor.columnCount.binding(onSet: model.commit)) {
                                Text("Auto").tag(ColumnCount.auto)
                                Text("1").tag(ColumnCount.one)
                                Text("2").tag(ColumnCount.two)
                            }
                        }
                    }
                }
                
                if let editor = model.epubEditor {
                    if editor.layout == .reflowable {
                        Section(header: Text("Typography")) {
                            Picker("Typeface", selection: editor.fontFamily.optionalBinding(onSet: model.commit)) {
                                Text("Original").tag(nil as FontFamily?)
                                ForEach(supportedFontFamilies, id: \.rawValue) { ff in
                                    Text(ff.rawValue).tag(ff as FontFamily?)
                                }
                            }
                            
                            HStack {
                                Button(action: { editor.fontSize.decrement(); model.commit() }) {
                                    Image(systemName: "textformat.size.smaller")
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                Spacer()
                                Text("Font Size: \(editor.fontSize.format(value: editor.fontSize.value ?? editor.fontSize.effectiveValue))")
                                    .font(.subheadline)
                                Spacer()
                                Button(action: { editor.fontSize.increment(); model.commit() }) {
                                    Image(systemName: "textformat.size.larger")
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            
                            if editor.fontWeight.isEffective {
                                HStack {
                                    Stepper("Font Weight", onIncrement: { editor.fontWeight.increment(); model.commit() }, onDecrement: { editor.fontWeight.decrement(); model.commit() })
                                    Text(editor.fontWeight.format(value: editor.fontWeight.value ?? editor.fontWeight.effectiveValue))
                                        .font(.caption)
                                }
                            }
                            
                            Toggle("Text Normalization", isOn: editor.textNormalization.binding(onSet: model.commit))
                            
                            if editor.ligatures.isEffective {
                                Toggle("Ligatures", isOn: editor.ligatures.binding(onSet: model.commit))
                            }
                        }
                        
                        Section(header: Text("Layout")) {
                            Toggle("Publisher Styles", isOn: editor.publisherStyles.binding(onSet: model.commit))
                            
                            if editor.textAlign.isEffective {
                                Picker("Alignment", selection: editor.textAlign.optionalBinding(onSet: model.commit)) {
                                    Text("Default").tag(nil as ReadiumNavigator.TextAlignment?)
                                    Text("Start").tag(ReadiumNavigator.TextAlignment.start as ReadiumNavigator.TextAlignment?)
                                    Text("Left").tag(ReadiumNavigator.TextAlignment.left as ReadiumNavigator.TextAlignment?)
                                    Text("Right").tag(ReadiumNavigator.TextAlignment.right as ReadiumNavigator.TextAlignment?)
                                    Text("Justify").tag(ReadiumNavigator.TextAlignment.justify as ReadiumNavigator.TextAlignment?)
                                }
                            }
                            
                            if editor.lineHeight.isEffective {
                                HStack {
                                    Stepper("Line Height", onIncrement: { editor.lineHeight.increment(); model.commit() }, onDecrement: { editor.lineHeight.decrement(); model.commit() })
                                    Text(editor.lineHeight.format(value: editor.lineHeight.value ?? editor.lineHeight.effectiveValue))
                                        .font(.caption)
                                }
                            }
                            
                            if editor.typeScale.isEffective {
                                HStack {
                                    Stepper("Type Scale", onIncrement: { editor.typeScale.increment(); model.commit() }, onDecrement: { editor.typeScale.decrement(); model.commit() })
                                    Text(editor.typeScale.format(value: editor.typeScale.value ?? editor.typeScale.effectiveValue))
                                        .font(.caption)
                                }
                            }
                            
                            if editor.wordSpacing.isEffective {
                                HStack {
                                    Stepper("Word Spacing", onIncrement: { editor.wordSpacing.increment(); model.commit() }, onDecrement: { editor.wordSpacing.decrement(); model.commit() })
                                    Text(editor.wordSpacing.format(value: editor.wordSpacing.value ?? editor.wordSpacing.effectiveValue))
                                        .font(.caption)
                                }
                            }
                            
                            if editor.letterSpacing.isEffective {
                                HStack {
                                    Stepper("Letter Spacing", onIncrement: { editor.letterSpacing.increment(); model.commit() }, onDecrement: { editor.letterSpacing.decrement(); model.commit() })
                                    Text(editor.letterSpacing.format(value: editor.letterSpacing.value ?? editor.letterSpacing.effectiveValue))
                                        .font(.caption)
                                }
                            }
                            
                            if editor.paragraphIndent.isEffective {
                                HStack {
                                    Stepper("Paragraph Indent", onIncrement: { editor.paragraphIndent.increment(); model.commit() }, onDecrement: { editor.paragraphIndent.decrement(); model.commit() })
                                    Text(editor.paragraphIndent.format(value: editor.paragraphIndent.value ?? editor.paragraphIndent.effectiveValue))
                                        .font(.caption)
                                }
                            }
                            
                            if editor.paragraphSpacing.isEffective {
                                HStack {
                                    Stepper("Paragraph Spacing", onIncrement: { editor.paragraphSpacing.increment(); model.commit() }, onDecrement: { editor.paragraphSpacing.decrement(); model.commit() })
                                    Text(editor.paragraphSpacing.format(value: editor.paragraphSpacing.value ?? editor.paragraphSpacing.effectiveValue))
                                        .font(.caption)
                                }
                            }
                            
                            if editor.hyphens.isEffective {
                                Toggle("Hyphens", isOn: editor.hyphens.binding(onSet: model.commit))
                            }
                            
                            if editor.verticalText.isEffective {
                                Toggle("Vertical Text", isOn: editor.verticalText.binding(onSet: model.commit))
                            }
                            
                            HStack {
                                Stepper("Page Margins", onIncrement: { editor.pageMargins.increment(); model.commit() }, onDecrement: { editor.pageMargins.decrement(); model.commit() })
                                Text(editor.pageMargins.format(value: editor.pageMargins.value ?? editor.pageMargins.effectiveValue))
                                    .font(.caption)
                            }
                            
                            verticalMarginStepper()
                        }
                    } else {
                        // Fixed-layout EPUB
                        Section(header: Text("Layout")) {
                            if editor.fit.isEffective {
                                Picker("Fit", selection: editor.fit.binding(onSet: model.commit)) {
                                    Text("Auto").tag(ReadiumNavigator.Fit.auto)
                                    Text("Page").tag(ReadiumNavigator.Fit.page)
                                    Text("Width").tag(ReadiumNavigator.Fit.width)
                                }
                            }
                            
                            if editor.spread.isEffective {
                                Picker("Spread", selection: editor.spread.binding(onSet: model.commit)) {
                                    Text("Auto").tag(ReadiumNavigator.Spread.auto)
                                    Text("Never").tag(ReadiumNavigator.Spread.never)
                                    Text("Always").tag(ReadiumNavigator.Spread.always)
                                }
                            }
                            
                            if editor.offsetFirstPage.isEffective {
                                Picker("Offset First Page", selection: editor.offsetFirstPage.optionalBinding(onSet: model.commit)) {
                                    Text("Auto").tag(nil as Bool?)
                                    Text("Yes").tag(true as Bool?)
                                    Text("No").tag(false as Bool?)
                                }
                            }
                            
                            verticalMarginStepper()
                        }
                    }
                } else if let editor = model.pdfEditor {
                    Section(header: Text("Layout")) {
                        if editor.fit.isEffective {
                            Picker("Fit", selection: editor.fit.binding(onSet: model.commit)) {
                                Text("Auto").tag(ReadiumNavigator.Fit.auto)
                                Text("Page").tag(ReadiumNavigator.Fit.page)
                                Text("Width").tag(ReadiumNavigator.Fit.width)
                            }
                        }
                        
                        if editor.spread.isEffective {
                            Picker("Spread", selection: editor.spread.binding(onSet: model.commit)) {
                                Text("Auto").tag(ReadiumNavigator.Spread.auto)
                                Text("Never").tag(ReadiumNavigator.Spread.never)
                                Text("Always").tag(ReadiumNavigator.Spread.always)
                            }
                        }
                        
                        if editor.offsetFirstPage.isEffective {
                            Picker("Offset First Page", selection: editor.offsetFirstPage.optionalBinding(onSet: model.commit)) {
                                Text("Auto").tag(nil as Bool?)
                                Text("Yes").tag(true as Bool?)
                                Text("No").tag(false as Bool?)
                            }
                        }
                        
                        if editor.pageSpacing.isEffective {
                            HStack {
                                Stepper("Page Spacing", onIncrement: { editor.pageSpacing.increment(); model.commit() }, onDecrement: { editor.pageSpacing.decrement(); model.commit() })
                                Text(editor.pageSpacing.format(value: editor.pageSpacing.value ?? editor.pageSpacing.effectiveValue))
                                    .font(.caption)
                            }
                        }
                        
                        verticalMarginStepper()
                        
                        if editor.scroll.isEffective {
                            if editor.scrollAxis.isEffective {
                                Picker("Scroll Axis", selection: editor.scrollAxis.binding(onSet: model.commit)) {
                                    Text("Vertical").tag(ReadiumNavigator.Axis.vertical)
                                    Text("Horizontal").tag(ReadiumNavigator.Axis.horizontal)
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                            
                            if editor.visibleScrollbar.isEffective {
                                Toggle("Visible Scrollbar", isOn: editor.visibleScrollbar.binding(onSet: model.commit))
                            }
                        }
                    }
                } else if !model.prefs.scroll {
                    // Fallback for Fixed-layout formats without a specialized editor (like CBZ/Images)
                    Section(header: Text("Layout")) {
                        verticalMarginStepper()
                    }
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(minWidth: 320, minHeight: 500)
    }
    
    @ViewBuilder private func verticalMarginStepper() -> some View {
        if !model.prefs.scroll {
            Stepper(value: Binding(
                get: { model.prefs.verticalMargin },
                set: { model.updateVerticalMargin($0) }
            ), in: 0.0...100.0, step: 5.0) {
                Text("Vertical Margin: \(Int(model.prefs.verticalMargin))pt")
            }
        }
    }
}
