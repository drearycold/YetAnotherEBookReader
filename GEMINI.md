# YetAnotherEBookReader (D.S.Reader)

YetAnotherEBookReader (publicly known as D.S.Reader) is a comprehensive e-book reader for iOS and macOS (via Catalyst). It supports EPUB, PDF, and CBZ formats and offers deep integration with Calibre Content Servers.

## Project Overview

- **Purpose**: A high-performance e-book reader with cloud synchronization via Calibre.
- **Main Technologies**:
  - **Frameworks**: SwiftUI (iOS 14+), UIKit.
  - **Reader Engines**: FolioReaderKit (EPUB), Readium R2 SDK (EPUB, PDF, CBZ).
  - **Data Persistence**: RealmSwift (Metadata, progress, highlights, shelf data).
  - **Networking**: GCDWebServer (Local content serving), Kingfisher (Image caching), Combine (Reactive state).
  - **Infrastructure**: CocoaPods (Dependency management), Carthage (Optional/Legacy dependencies).

## Architecture

- **`ModelData`**: The central `@StateObject` that manages application state, database initialization, server connectivity, and book metadata.
- **`YabrEBookReader`**: A routing layer that selects the appropriate reader engine based on book format and user preference.
- **`CalibreServerService`**: Handles all API interactions with Calibre servers.
- **Local Web Server**: Uses `GCDWebServer` to serve book assets locally to web-based reader views (like FolioReader), ensuring high performance and compatibility.

## Building and Running

### Prerequisites
- Xcode 13+ (Supporting iOS 14.0+ / macOS 11.0+)
- CocoaPods (`gem install cocoapods`)
- `cocoapods-patch` plugin (`gem install cocoapods-patch`)

### Steps
1.  **Install Dependencies**:
    ```bash
    pod install
    ```
    *Note: If there are Carthage dependencies, run `./makedeps.sh`.*
2.  **Open Workspace**:
    ```bash
    open YetAnotherEBookReader.xcworkspace
    ```
3.  **Select Target**:
    - `YetAnotherEBookReader` for iOS.
    - `YetAnotherEBookReader-Catalyst` for macOS.
4.  **Build & Run**: Press `Cmd + R` in Xcode.

## Development Conventions

- **State Management**: Always use `ModelData.shared` or `@EnvironmentObject var modelData: ModelData` for app-wide state.
- **Database**:
  - Use Realm for all persistent data.
  - Database migrations MUST be registered in `ModelData.swift` within `tryInitializeDatabase`.
  - Prefer using `ModelData.RealmSchemaVersion` for tracking schema updates.
- **Reader Integration**:
  - New reader engines should be implemented as `UIViewController` containers.
  - Integration into the app should be done via `EBookReaderSwiftUI` (`UIViewControllerRepresentable`).
- **Asynchronous Operations**: Extensively use `Combine` and `DispatchQueue` for non-blocking I/O and server requests.
- **Resource Management**: Large files (books) are managed via `Downloader.swift` and served locally via `GCDWebServer` in `EpubFolioReaderContainer.swift`.

## Key Directories
- `YetAnotherEBookReader/Models/`: Data models and core logic (`ModelData.swift`, `Book.swift`, `RealmModel.swift`).
- `YetAnotherEBookReader/Views/`: SwiftUI views for the main interface and reader wrappers.
- `YetAnotherEBookReader/Network/`: Networking logic and server services.
- `YetAnotherEBookReader/Views/FolioReaderView/`: Specific implementation for the FolioReader engine, including the local web server.
