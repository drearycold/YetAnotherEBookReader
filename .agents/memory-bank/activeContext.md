# Active Context

## Current Focus
The primary development focus is executing Phase 1 of the SwiftUI MVVM Refactoring Plan. We are systematically decoupling massive SwiftUI views from the `ModelData` "God Object" and introducing dedicated ViewModels to handle business logic and state.

## Recent Changes & Decisions
- **Development Environment Migration:** Transitioning the project to an agent-first development workflow using the Google Antigravity CLI.
- **Architectural Shift (MVVM):** Transitioning from a single monolithic `@EnvironmentObject var modelData` to modular `@StateObject` ViewModels for complex views.
- **Context Guardrails:** Established the `.agents/memory-bank` directory to provide strict architectural guidelines, preventing subagents from hallucinating or deviating from the Swift Package Manager / SwiftUI architecture.
- **MCP Integration:** Moved Xcode toolchain configurations to `.agents/mcp_config.json` to allow the Antigravity CLI to autonomously interact with `xcodebuild` and the iOS Simulator.

## Active Tasks
- [x] 1. Expand `BookDetailViewModel.swift` to handle all data fetching (metadata, manifest) and UI state variables currently trapped in `BookDetailView.swift`.
- [x] 2. Break down the massive `BookDetailView.swift` (800+ lines) into smaller, manageable subcomponents (`BookDetailSubviews.swift`).
- [x] 3. Replace direct `ModelData` network calls inside `BookDetailView` with unidirectional data flow via `BookDetailViewModel`.
- [x] 4. Compile the project in the terminal using `xcodebuild` to ensure the SwiftUI refactoring doesn't break the build and unit tests pass.
- [x] 5. Successfully decoupled `ModelData` from all `BookDetailView` subviews (`BookCoverView`, `BookMetadataSection`, `BookConnectivitySection`, `BookFormatList`, `BookProgressSection`) by passing state through `BookDetailViewModel`.
- [x] 6. Decoupled `BookDownloadManager` from `BookDetailView` and `BookDetailSubviews` by mapping `activeDownloads` into `BookDetailViewModel` using Combine.
- [x] 7. Decoupled `ModelData` from `BookDetailView`'s state presentation stack, book conversion, and metadata status, proxying them through `BookDetailViewModel`. Unit tests added and verified.
- [x] 8. Migrated presentation state variables (`presentingReadingSheet`, `presentingPreviewSheet`, `activityListViewPresenting`, `readingPositionHistoryViewPresenting`) from `BookDetailView` to `BookDetailViewModel`, utilizing custom Binding wrappers in property observers.
- [x] 9. Decoupled `BookDetailView` entirely from `@EnvironmentObject var modelData`, utilizing dependency injection of `ModelData.shared` inside the ViewModel.
- [x] 10. Enforced MVVM architecture on Reading Position views (`ReadingPositionHistoryView` and `ReadingPositionDetailView`), decoupling them from `ModelData` and Realm queries via `ReadingPositionHistoryViewModel` and `ReadingPositionDetailViewModel`.

## Next Steps
- [ ] 11. Apply similar MVVM componentization to other large views (e.g., `LibraryInfoBookListView`).
- [ ] 12. Decouple `CalibreServerService` and remaining `ModelData` dependencies.

## Active Constraints
- **Do NOT** introduce CocoaPods or modify workspace files; the project relies entirely on Swift Package Manager.
- **Decoupling Goal:** Views should minimize direct dependency on `ModelData` for network operations; logic should reside in dedicated ViewModels.
