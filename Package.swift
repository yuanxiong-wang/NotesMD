// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotesMD",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NotesMDCore", targets: ["NotesMDCore"]),
        .executable(name: "NotesMD", targets: ["NotesMD"])
    ],
    targets: [
        .target(
            name: "NotesMDCore",
            path: "Sources/NotesMDCore"
        ),
        .executableTarget(
            name: "NotesMD",
            dependencies: ["NotesMDCore"],
            path: "Sources/NotesMD"
        ),
        .executableTarget(
            name: "notesmd-check",
            dependencies: ["NotesMDCore"],
            path: "Sources/NotesMDCheck"
        )
    ]
)
