# Contributing to Profile Shelf

Small, focused contributions are welcome: reproducible bug reports, documentation improvements, accessibility fixes, and support for more apps.

1. Create a branch in your copy of the source.
2. Run `bash build.sh` on an Apple Silicon Mac with full Xcode installed. This runs XCTest, standalone checks, and package verification.
3. Explain the change and how you checked it. Include screenshots with fictional or empty profiles for UI changes.

Use the existing native SwiftUI and AppKit stack. Keep profile data local. Never include real account files, tokens, client names, personal icons, or private task content in a commit or issue. Tests must use temporary profile homes and must not stop or update the developer's real provider apps.
