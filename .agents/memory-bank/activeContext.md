# Active Context

## Current Focus
The primary development focus is to use the Readium engine to optimize the loading performance of PDF bookmarks. 

## Recent Changes & Decisions
- **Development Environment Migration:** Transitioning the project to an agent-first development workflow using the Google Antigravity CLI.
- **Context Guardrails:** Established the `.agents/memory-bank` directory to provide strict architectural guidelines, preventing subagents from hallucinating or deviating from the Swift Package Manager / SwiftUI architecture.
- **MCP Integration:** Moved Xcode toolchain configurations to `.agents/mcp_config.json` to allow the Antigravity CLI to autonomously interact with `xcodebuild` and the iOS Simulator.

## Active Tasks
1. Analyze the current PDF bookmark parsing and loading mechanisms within the `YetAnotherEBookReader/Readium/` integration and associated PDF model files (`Models/BookAnnotation.swift`, `YabrPDFModel.swift`).
2. Identify performance bottlenecks occurring during the rendering of large PDF bookmark trees via the Readium 3.8 SDK.
3. Implement performance optimizations (e.g., lazy loading, background threading via `DispatchQueue` or Combine) without blocking the main UI thread.
4. Compile the project in the terminal using the command: `xcodebuild build -scheme YetAnotherEBookReader -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=latest'` to verify build integrity.
5. Verify the performance improvements in the iOS Simulator.

## Active Constraints
- **Do NOT** introduce CocoaPods or modify workspace files; the project relies entirely on Swift Package Manager.
- All UI state changes must be routed through the existing `ModelData` implementation using Combine.

