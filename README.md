# YetAnotherEBookReader (D.S.Reader)

**D.S.Reader** is a versatile and modern e-book reader for iOS and macOS (via Catalyst). It supports a wide range of formats including EPUB, PDF, and CBZ, with a strong focus on high-performance rendering and seamless integration with Calibre content servers.

## Key Features

- **Multi-Format Support**: Native rendering for EPUB, PDF, and CBZ.
- **Readium 3.8 Integration**: Leverages the latest Readium R2 SDK for advanced layout, accessibility, and stable performance.
- **Calibre Sync**: Deep integration with Calibre content servers for cloud synchronization of libraries and reading progress.
- **Modernized UI**: Unified SwiftUI settings and navigation panels for a consistent experience across all formats.
- **Advanced Reader Features**:
  - **Dynamic Margins**: Customize vertical and horizontal spacing in real-time.
  - **Theme Support**: Light, Dark, and Sepia themes with automatic image filtering.
  - **Volume Key Paging**: Use physical volume buttons to turn pages.
  - **RTL Support**: Full support for Right-to-Left reading progressions.
  - **Accessibility**: Optimized for VoiceOver with dedicated navigation controls.

## Architecture & Technology

- **UI Framework**: SwiftUI (iOS 15+) and UIKit.
- **Engines**: Readium 3.8 (EPUB, PDF, CBZ) and FolioReaderKit (Legacy EPUB).
- **Persistence**: RealmSwift for metadata, highlights, and cross-device sync.
- **Networking**: GCDWebServer for local content serving and Kingfisher for efficient image caching.
- **Dependencies**: Pure Swift Package Manager (SPM).

## Development

### Requirements
- Xcode 15.0+
- iOS 15.0+ / macOS 12.0+ (Catalyst)

### Build Commands
To build the project from the terminal:

**iOS Simulator:**
```bash
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
```

**Mac Catalyst:**
```bash
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader-Catalyst -destination 'platform=macOS,variant=Mac Catalyst' build
```

## Contributing

Please refer to `GEMINI.md` for technical standards, architectural details, and development conventions used in this project.

## License

This project is licensed under the terms found in `Privacy.md` and `Terms.md`. See the `Settings.bundle` for third-party license information.
