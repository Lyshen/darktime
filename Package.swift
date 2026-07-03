// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Darktime",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "darktime", targets: ["Darktime"])
    ],
    targets: [
        .executableTarget(
            name: "Darktime",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Darktime/Info.plist"
                ])
            ]
        )
    ]
)
