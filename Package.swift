// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DynamicIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DynamicIsland",
            path: "Sources/DynamicIsland",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("QuickLookThumbnailing"),
            ]
        )
    ]
)
