# YetAnotherEBookReader (D.S.Reader)

YetAnotherEBookReader (publicly known as D.S.Reader) is a comprehensive e-book reader for iOS and macOS (via Catalyst). It supports EPUB, PDF, and CBZ formats and offers deep integration with Calibre Content Servers.

## Project Overview

- **Purpose**: A high-performance e-book reader with cloud synchronization via Calibre.
- **Main Technologies**:
  - **Frameworks**: SwiftUI (iOS 15+), UIKit.
  - **Reader Engines**: FolioReaderKit (EPUB), Readium R2 SDK (EPUB, PDF, CBZ).
  - **Data Persistence**: RealmSwift (Metadata, progress, highlights, shelf data).
  - **Networking**: GCDWebServer (Local content serving), Kingfisher (Image caching), Combine (Reactive state).
  - **Infrastructure**: Swift Package Manager (SPM) for dependency management.

## Architecture

- **`ModelData`**: The central `@StateObject` that manages application state, database initialization, server connectivity, and book metadata. Located in `YetAnotherEBookReader/Models/ModelData.swift`.
- **`YetAnotherEBookReaderApp`**: The SwiftUI App entry point that initializes `ModelData` and handles scene phase changes.
- **`CalibreServerService`**: Handles all API interactions with Calibre servers.
- **Reader Integration**: Uses `FolioReaderKit` and `Readium` for rendering different book formats.
- **Local Web Server**: Uses `GCDWebServer` to serve book assets locally to web-based reader views.

## Building and Running

The project is an SPM-based Xcode project. It does **not** use CocoaPods or a Workspace.

### Commands for Terminal Compilation

#### Build for iOS Simulator:
```bash
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
```

#### Build for Mac Catalyst:
```bash
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader-Catalyst -destination 'platform=macOS,variant=Mac Catalyst' build
```

### Development Environment
- **Xcode**: Supporting iOS 15.0+ / macOS 12.0+ (Catalyst).
- **Dependencies**: Managed via `YetAnotherEBookReader.xcodeproj`'s Swift Packages.

## Development Conventions

- **State Management**: Use `@EnvironmentObject var modelData: ModelData` for app-wide state.
- **Database**:
  - Realm is used for persistent data.
  - Initialize the database via `modelData.tryInitializeDatabase()`.
- **Info.plist**:
  - iOS target uses `YetAnotherEBookReader/Info.plist`.
  - Catalyst target uses `YetAnotherEBookReader for macOS/Info.plist`.
- **Asynchronous Operations**: Extensively use `Combine` and `DispatchQueue` for non-blocking I/O and server requests.
- **Resource Management**: Large files (books) are managed via `Downloader.swift` and served locally where required by the reader engine.

## Key Directories
- `YetAnotherEBookReader/Models/`: Data models and core logic (`ModelData.swift`, `Book.swift`, `RealmModel.swift`).
- `YetAnotherEBookReader/Views/`: SwiftUI views for the main interface and reader wrappers.
- `YetAnotherEBookReader/Network/`: Networking logic and server services.
- `YetAnotherEBookReader/Readium/`: Readium R2 SDK integration.
- `YetAnotherEBookReader for macOS/`: Specific resources for the Catalyst/macOS target.
