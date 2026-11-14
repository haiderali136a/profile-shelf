// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProfileShelf",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ProfileShelfLauncher", targets: ["ProfileShelfLauncher"]), .executable(name: "ProfileShelf", targets: ["ProfileShelf"]), .executable(name: "ProfileShelfClaude", targets: ["ProfileShelfClaude"]), .executable(name: "ProfileShelfShim", targets: ["ProfileShelfShim"]), .executable(name: "ProfileShelfContext", targets: ["ProfileShelfContext"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [
        .target(name: "DockCore"),
        .executableTarget(name: "ProfileShelfLauncher"),
        .executableTarget(name: "ProfileShelfClaude", dependencies: ["DockCore"]),
        .executableTarget(name: "ProfileShelfShim", dependencies: ["DockCore"]),
        .target(name: "ContextCore", dependencies: ["DockCore"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "ProfileShelfContext", dependencies: ["ContextCore"]),
        .executableTarget(name: "ProfileShelf", dependencies: ["DockCore", "ContextCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "ContextCoreTests", dependencies: ["ContextCore"]),
        .testTarget(name: "DockCoreTests", dependencies: ["DockCore"]),
        .testTarget(name: "ProfileShelfTests", dependencies: ["ProfileShelf"])
    ],
    swiftLanguageModes: [.v5]
)
